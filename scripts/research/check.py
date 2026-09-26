#!/usr/bin/env python3
"""Run focused behavioral tests with archived settings and separate size gates."""

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from contextlib import contextmanager
from bytecode import sources as collect_sources

ROOT = Path(__file__).resolve().parents[2]


@contextmanager
def temporary_config(config):
    path = ROOT / 'foundry.toml'
    original = path.read_text()
    path.write_text(config)
    try:
        yield
    finally:
        if path.read_text() != config:
            raise RuntimeError('foundry.toml changed during the run; refusing to overwrite it')
        path.write_text(original)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt", type=Path)
    parser.add_argument("--scope", choices=("calls", "market", "hooks", "storage", "arithmetic", "invariants", "deployment", "all"), default="all")
    parser.add_argument("--runs", type=int, default=44)
    parser.add_argument("--yul-steps")
    parser.add_argument("--gates", action="store_true")
    parser.add_argument("--code-size-limit", type=int, default=262144)
    parser.add_argument("--no-dynamic-test-linking", action="store_true")
    parser.add_argument("--solc", type=Path, help="optional compiler path for diagnostics")
    args = parser.parse_args()
    args.receipt.mkdir(parents=True, exist_ok=False)
    config = (ROOT / "foundry.toml").read_text()
    # keep artifacts at the usual path: production artifact tests read deploy-out explicitly.
    config += "\n[profile.research]\nout = 'deploy-out'\ncache_path = 'deploy-cache'\n"
    config += "extra_output_files = ['irOptimized', 'ir']\n"
    config += "extra_output = ['storageLayout']\n"
    config += "optimizer_runs = " + str(args.runs) + "\n"
    if args.no_dynamic_test_linking:
        config += "dynamic_test_linking = false\n"
    if args.yul_steps:
        config += "optimizer_details = { yulDetails = { optimizerSteps = " + json.dumps(args.yul_steps) + " } }\n"
    (args.receipt / "foundry.toml").write_text(config)
    command = ["forge", "test", "--root", str(ROOT), "--code-size-limit", str(args.code_size_limit), "--fuzz-seed", "0x5eed", "--skip", "script", "-vv"]
    if args.solc:
        command += ["--use", str(args.solc)]
    include = {ROOT / "test/libraries/LibFixedCall.t.sol"}
    if args.scope in ("market", "all"):
        include |= set(ROOT.glob("test/market/*.t.sol"))
        include |= {ROOT / "test/integration/RepaymentPrototype.t.sol"}
        include |= {ROOT / ("test/libraries/" + name + ".t.sol") for name in ("MarketLifecycle", "MarketEvents", "BoolUtils", "MarketState", "BoundedMarketState")}
    if args.scope in ("hooks", "all"):
        include |= set(ROOT.glob("test/access/*.t.sol")) | set(ROOT.glob("test/factories/*.t.sol"))
    if args.scope in ("storage", "all"):
        include |= {ROOT / ("test/libraries/" + name + ".t.sol") for name in ("LibStoredInitCode", "CompressedInitCode")}
    if args.scope in ("arithmetic", "all"):
        include |= {ROOT / ("test/libraries/" + name + ".t.sol") for name in ("MathUtils", "FeeMath", "SafeCastLib")}
    if args.scope in ("invariants", "all"):
        include |= set(ROOT.glob("test/invariants/*.t.sol"))
    if args.scope == "invariants":
        include.discard(ROOT / "test/libraries/LibFixedCall.t.sol")
    if args.scope == "deployment":
        include = {ROOT / "test/research/SingleStorageDeployment.t.sol"}
    include = {path for path in include if path.exists()}
    # archive uncommitted experiments too; HEAD alone does not identify what Forge tested.
    sources = {
        path.relative_to(ROOT).as_posix(): path.read_text()
        for directory in (ROOT / 'src', ROOT / 'test')
        for path in sorted(directory.rglob('*.sol'))
    }
    (args.receipt / 'project-sources.json').write_text(json.dumps(sources, indent=2) + '\n')
    (args.receipt / 'source-hashes.json').write_text(json.dumps({
        path: hashlib.sha256(content.encode()).hexdigest() for path, content in sources.items()
    }, indent=2) + '\n')
    roots = {path.relative_to(ROOT).as_posix() for path in include | set(ROOT.glob('src/**/*.sol'))}
    while True:
        reachable = collect_sources(roots)
        # artifact deployment uses string paths too; keep those contracts in the build graph.
        artifacts = {
            name
            for source in reachable.values()
            for name in re.findall(r"['\"]([^'\"\n]+\.sol):[^'\"\n]+['\"]", source['content'])
            if (ROOT / name).is_file()
        }
        missing = artifacts - reachable.keys()
        if not missing:
            break
        roots |= missing
    (args.receipt / 'reachable-sources.json').write_text(json.dumps(sorted(reachable), indent=2) + '\n')
    for path in sorted(ROOT.glob("test/**/*.sol")):
        if path.relative_to(ROOT).as_posix() not in reachable:
            command += ["--skip", path.relative_to(ROOT).as_posix()]
    gate_pattern = "(test_ProductionArtifactsFitActualCodeStorageAndRuntimeLimits|test_composition_FitsRuntimeAndStoredInitcodeLimits)"
    command += ["--match-test" if args.gates else "--no-match-test", gate_pattern]
    env = {**os.environ, "FOUNDRY_PROFILE": "research"}
    with temporary_config(config):
        config_result = subprocess.run(["forge", "config", "--json"], env=env, cwd=ROOT, text=True, capture_output=True, check=True)
        effective = json.loads(config_result.stdout)
        assert effective["optimizer_runs"] == args.runs
        if args.no_dynamic_test_linking:
            assert effective["dynamic_test_linking"] is False
        if args.yul_steps:
            assert effective["optimizer_details"]["yulDetails"]["optimizerSteps"] == args.yul_steps
        (args.receipt / "effective-config.json").write_text(config_result.stdout)
        record = {"command": command, "head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(), "started": datetime.datetime.now(datetime.timezone.utc).isoformat(), "selected_files": [str(path.relative_to(ROOT)) for path in sorted(include)]}
        print("Testing", len(include), "selected files", flush=True)
        with (args.receipt / "tests.log").open("w") as log:
            result = subprocess.run(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
    record["exit_code"] = result.returncode
    record["completed"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    (args.receipt / "receipt.json").write_text(json.dumps(record, indent=2) + "\n")
    output = (args.receipt / "tests.log").read_text()
    print(output[-12000:], flush=True)
    if result.returncode == 0 and "tests passed" not in output and "test passed" not in output:
        raise SystemExit("No tests ran; this is not a passing qualification.")
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
