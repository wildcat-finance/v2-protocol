#!/usr/bin/env python3
"""Run matched gas scenarios in a detached worktree with archived configuration."""

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tomllib

ROOT = Path(__file__).resolve().parents[2]


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt", type=Path)
    parser.add_argument("--ref", required=True)
    parser.add_argument("--runs", type=int, required=True)
    parser.add_argument("--yul", choices=("adopted", "default"), required=True)
    parser.add_argument("--legacy", action="store_true", help="only common scenarios, no new lifecycle calls")
    parser.add_argument("--reuse-worktree", type=Path, help="reuse a completed benchmark worktree and its compile cache")
    args = parser.parse_args()
    args.receipt = args.receipt.resolve()
    args.receipt.mkdir(parents=True, exist_ok=False)
    tree = args.reuse_worktree.resolve() if args.reuse_worktree else args.receipt / "worktree"
    head = subprocess.check_output(["git", "rev-parse", args.ref], cwd=ROOT, text=True).strip()
    if args.reuse_worktree:
        assert subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=tree, text=True).strip() == head
    else:
        subprocess.run(["git", "worktree", "add", "--detach", str(tree), head], cwd=ROOT, check=True)
    # use the checked-out dependency contents, and archive their hashes below.
    shutil.copytree(ROOT / "lib", tree / "lib", dirs_exist_ok=True, ignore=shutil.ignore_patterns(".git"))
    for dependency in (ROOT / "lib").iterdir():
        if not (dependency / ".git").exists():
            continue
        git_directory = subprocess.check_output(
            ["git", "-C", str(dependency), "rev-parse", "--absolute-git-dir"], text=True
        ).strip()
        (tree / "lib" / dependency.name / ".git").write_text(f"gitdir: {git_directory}\n")
    fixtures = tree / "scripts/research/fixtures"
    fixtures.mkdir(parents=True, exist_ok=True)
    names = ["MarketGas.t.sol"] + ([] if args.legacy else ["MarketLifecycleGas.t.sol"])
    for name in names:
        shutil.copyfile(ROOT / "scripts/research/fixtures" / name, fixtures / name)
    # vm.getCode names this artifact without a Solidity import in the shared fixture.
    (fixtures / "GasArtifactRoots.sol").write_text(
        "pragma solidity 0.8.25;\nimport 'src/market/WildcatMarketRevolving.sol';\n"
    )
    original_config = subprocess.check_output(["git", "show", f"{head}:foundry.toml"], cwd=ROOT, text=True)
    config = re.sub(r"^optimizer_runs\s*=.*$", f"optimizer_runs = {args.runs}", original_config, flags=re.M)
    config = re.sub(r"^optimizer_details\s*=.*\n", "", config, flags=re.M)
    details = tomllib.loads((ROOT / "foundry.toml").read_text())["profile"]["default"]["optimizer_details"]
    if args.yul == "adopted":
        steps = details["yulDetails"]["optimizerSteps"]
        config = config.replace(
            f"optimizer_runs = {args.runs}",
            f"optimizer_runs = {args.runs}\noptimizer_details = {{ yulDetails = {{ optimizerSteps = '{steps}' }} }}",
            1,
        )
    config += """
[profile.research_gas]
test = 'scripts/research/fixtures'
script = 'scripts/coverage-root'
out = 'out'
cache_path = 'gas-cache'
isolate = true
dynamic_test_linking = true
gas_reports = ['WildcatMarket', 'WildcatMarketRevolving', 'OpenTermHooks', 'FixedTermHooks', 'PeriodicTermHooks']
"""
    (tree / "foundry.toml").write_text(config)
    (args.receipt / "original-foundry.toml").write_text(original_config)
    (args.receipt / "measured-foundry.toml").write_text(config)
    env = {key: value for key, value in os.environ.items() if not key.startswith(("FOUNDRY_", "DAPP_", "FORGE_SNAPSHOT_"))}
    env["FOUNDRY_PROFILE"] = "research_gas"
    effective = subprocess.check_output(["forge", "config", "--json"], cwd=tree, env=env, text=True)
    (args.receipt / "effective-config.json").write_text(effective)
    effective_config = json.loads(effective)
    assert effective_config["isolate"] and effective_config["optimizer_runs"] == args.runs
    assert effective_config["via_ir"] and effective_config["evm_version"] == "cancun"
    if args.yul == "adopted":
        assert effective_config["optimizer_details"]["yulDetails"]["optimizerSteps"] == steps
    else:
        assert not effective_config.get("optimizer_details"), effective_config.get("optimizer_details")
    texts = {
        p.relative_to(tree).as_posix(): p.read_text()
        for folder in ("src", "test/shared", "test/mocks", "lib", "scripts/research/fixtures")
        for p in sorted((tree / folder).rglob("*.sol"))
    }
    save(args.receipt / "source-texts.json", texts)
    command = ["forge", "test", "--offline", "--match-contract", "^(MarketGasTest|MarketLifecycleGasTest)$", "--code-size-limit", "200000", "--block-timestamp", "1724284800", "--gas-report", "--summary", "--json-file", str(args.receipt / "tests.json")]
    record = {
        "head": head,
        "runs": args.runs,
        "yul": args.yul,
        "legacy": args.legacy,
        "worktree": str(tree),
        "command": command,
        "forge": subprocess.check_output(["forge", "--version"], text=True),
        "source_sha256": {p: hashlib.sha256(text.encode()).hexdigest() for p, text in texts.items()},
        "started": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }
    save(args.receipt / "receipt.json", record)
    if (tree / "snapshots").exists():
        shutil.move(tree / "snapshots", args.receipt / "prior-snapshots")
    with (args.receipt / "tests.log").open("w") as output, (args.receipt / "stderr.log").open("w") as error:
        result = subprocess.run(command, cwd=tree, env=env, stdout=output, stderr=error)
    record["exit_code"] = result.returncode
    record["completed"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    save(args.receipt / "receipt.json", record)
    result.check_returncode()
    snapshots = {p.stem: json.loads(p.read_text()) for p in sorted((tree / "snapshots").glob("*.json"))}
    assert len(snapshots) == (6 if args.legacy else 10), ("unexpected snapshot groups", list(snapshots))
    states = {name: values.pop("state-fingerprint") for name, values in snapshots.items()}
    assert sum(map(len, snapshots.values())) == (104 if args.legacy else 134), "incomplete scenario snapshots"
    save(args.receipt / "states.json", states)
    save(args.receipt / "gas.json", snapshots)
    shutil.copytree(tree / "snapshots", args.receipt / "snapshots")
    print(f"{args.receipt.name}: {sum(len(v) for v in snapshots.values())} call snapshots in {len(snapshots)} groups", flush=True)


if __name__ == "__main__":
    main()
