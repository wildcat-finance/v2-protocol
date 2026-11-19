#!/usr/bin/env python3
"""Measure a runs range without editing Foundry configuration or build artifacts."""

import argparse
import concurrent.futures
import copy
import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tomllib

sys.dont_write_bytecode = True
import bytecode as research


def sha256(value):
    return hashlib.sha256(value).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt", type=Path)
    parser.add_argument("--first", type=int, default=1)
    parser.add_argument("--last", type=int, default=44)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--forge-reference", type=Path, required=True)
    parser.add_argument("--solc", type=Path, default=Path.home() / ".local/share/svm/0.8.25/solc-0.8.25")
    args = parser.parse_args()
    if not 1 <= args.first <= args.last or args.workers < 1:
        parser.error("require 1 <= first <= last and at least one worker")
    args.receipt.mkdir(parents=True, exist_ok=False)
    root = research.ROOT
    config_bytes = (root / "foundry.toml").read_bytes()
    config = tomllib.loads(config_bytes.decode())["profile"]["default"]
    if args.first != config["optimizer_runs"]:
        parser.error("start the sweep at the adopted optimizer_runs value to qualify the reference")
    targets = research.TARGETS | {
        name: f"src/lens/{name}.sol"
        for name in ("MarketLens", "MarketLensCore", "MarketLensAggregator", "MarketLensLive")
    }
    source_texts = research.sources(targets.values())
    settings = {
        "remappings": research.REMAPPINGS,
        "optimizer": {
            "enabled": True,
            "runs": config["optimizer_runs"],
            "details": config["optimizer_details"],
        },
        "metadata": {"useLiteralContent": False, "bytecodeHash": "none", "appendCBOR": False},
        "evmVersion": "cancun",
        "viaIR": True,
        "libraries": {},
        "outputSelection": {
            path: {name: ["abi", "evm.bytecode.object", "evm.deployedBytecode.object", "storageLayout"]}
            for name, path in targets.items()
        },
    }
    references = {
        name: json.loads((args.forge_reference / Path(path).name / f"{name}.json").read_text())
        for name, path in targets.items()
    }
    manifest = {
        "head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
        "compiler": subprocess.check_output([str(args.solc), "--version"], text=True).strip(),
        "compiler_sha256": sha256(args.solc.read_bytes()),
        "config_sha256": sha256(config_bytes),
        "source_sha256": {path: sha256(value["content"].encode()) for path, value in source_texts.items()},
        "first": args.first,
        "last": args.last,
        "workers": args.workers,
        "settings": settings,
        "reference": str(args.forge_reference.resolve()),
        "reference_hashes": {
            name: {field: sha256(bytes.fromhex(artifact[field]["object"].removeprefix("0x")))
                   for field in ("bytecode", "deployedBytecode")}
            for name, artifact in references.items()
        },
        "started": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }
    save(args.receipt / "manifest.json", manifest)
    baseline_layouts = {}

    def measure(runs):
        directory = args.receipt / f"runs-{runs:02d}"
        directory.mkdir()
        point_settings = copy.deepcopy(settings)
        point_settings["optimizer"]["runs"] = runs
        compiler_input = {"language": "Solidity", "sources": source_texts, "settings": point_settings}
        save(directory / "input.json", compiler_input)
        with (directory / "input.json").open() as stdin, (directory / "output.json").open("w") as stdout, (directory / "stderr.log").open("w") as stderr:
            result = subprocess.run([str(args.solc), "--standard-json"], stdin=stdin, stdout=stdout, stderr=stderr, cwd=root)
        result.check_returncode()
        output = json.loads((directory / "output.json").read_text())
        errors = [e for e in output.get("errors", []) if e["severity"] == "error"]
        if errors:
            raise RuntimeError("\n".join(e["formattedMessage"] for e in errors))
        rows = []
        for name, path in targets.items():
            artifact = output["contracts"][path][name]
            evm = artifact["evm"]
            reference = references[name]
            assert research.normalized_abi(artifact["abi"]) == research.normalized_abi(reference["abi"]), (runs, name, "ABI")
            layout = research.normalized_layout(artifact["storageLayout"])
            if runs == args.first:
                baseline_layouts[name] = layout
            assert layout == baseline_layouts[name], (runs, name, "layout")
            if "storageLayout" in reference:
                assert layout == research.normalized_layout(reference["storageLayout"]), (runs, name, "reference layout")
            row = {
                "contract": name,
                "creation": len(evm["bytecode"]["object"]) // 2,
                "runtime": len(evm["deployedBytecode"]["object"]) // 2,
                "abi_unchanged": True,
                "layout_unchanged": True,
            }
            row["runtime_headroom"] = 24_576 - row["runtime"]
            row["creation_headroom"] = 49_152 - row["creation"]
            for field in ("bytecode", "deployedBytecode"):
                row[field + "_sha256"] = sha256(bytes.fromhex(evm[field]["object"]))
                if runs == config["optimizer_runs"]:
                    assert evm[field]["object"] == reference[field]["object"].removeprefix("0x"), (runs, name, field, "reference mismatch")
            rows.append(row)
        result = {"runs": runs, "contracts": rows, "runtime_fits": all(r["runtime_headroom"] >= 0 for r in rows)}
        save(directory / "sizes.json", result)
        markets = ", ".join(f"{r['contract']}={r['runtime']}" for r in rows[:2])
        print(f"runs {runs:2d}: {markets}; all runtimes fit={result['runtime_fits']}", flush=True)
        return result

    # qualify the source graph against the canonical build before parallel points.
    points = [measure(args.first)]
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        points.extend(pool.map(measure, range(args.first + 1, args.last + 1)))
    assert (root / "foundry.toml").read_bytes() == config_bytes, "Foundry configuration changed during measurement"
    assert research.sources(targets.values()) == source_texts, "measured source changed during measurement"
    manifest["completed"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    save(args.receipt / "manifest.json", manifest)
    save(args.receipt / "sizes.json", points)
    with (args.receipt / "sizes.tsv").open("w") as table:
        table.write("runs\t" + "\t".join(targets) + "\tall_runtime_fit\n")
        for point in points:
            table.write(str(point["runs"]) + "\t" + "\t".join(str(row["runtime"]) for row in point["contracts"]) + f"\t{point['runtime_fits']}\n")


if __name__ == "__main__":
    main()
