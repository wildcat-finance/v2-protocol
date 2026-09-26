#!/usr/bin/env python3
"""Reproducible size experiments; big compiler receipts stay outside the repo."""

import argparse
import datetime
import hashlib
import json
import posixpath
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
TARGETS = {
    "WildcatMarket": "src/market/WildcatMarket.sol",
    "WildcatMarketRevolving": "src/market/WildcatMarketRevolving.sol",
    "OpenTermHooks": "src/access/OpenTermHooks.sol",
    "FixedTermHooks": "src/access/FixedTermHooks.sol",
    "PeriodicTermHooks": "src/access/PeriodicTermHooks.sol",
    "HooksFactory": "src/HooksFactory.sol",
    "HooksFactoryRevolving": "src/HooksFactoryRevolving.sol",
    "PeriodicTransferHooks": "test/mocks/TransferFeatureHooks.sol",
    "PeriodicBorrowHooks": "test/mocks/BorrowFeatureHooks.sol",
    "PeriodicAprReplacementHooks": "test/mocks/AprReplacementHooks.sol",
}
REMAPPINGS = [
    "forge-std/=lib/forge-std/src/",
    "solmate/=lib/solmate/src/",
    "solady/=lib/solady/src/",
    "openzeppelin/=lib/openzeppelin-contracts/",
    "openzeppelin-contracts/=lib/openzeppelin-contracts/",
]


def sources():
    result = {}

    def visit(path):
        if path in result:
            return
        content = (ROOT / path).read_text()
        result[path] = {"content": content}
        for statement in re.findall(r"\bimport\s+[^;]+;", content):
            imported = re.findall(r"['\"]([^'\"]+)['\"]", statement)[-1]
            if imported.startswith("."):
                imported = posixpath.normpath(posixpath.join(posixpath.dirname(path), imported))
            else:
                for mapping in REMAPPINGS:
                    prefix, replacement = mapping.split("=", 1)
                    if imported.startswith(prefix):
                        imported = replacement + imported[len(prefix):]
                        break
            visit(imported)

    for path in TARGETS.values():
        visit(path)
    return dict(sorted(result.items()))


def normalized_layout(layout):
    types = layout.get("types") or {}

    def canonical(type_id):
        node = types[type_id]
        result = {key: node[key] for key in ("label", "encoding", "numberOfBytes")}
        for key in ("key", "value", "base"):
            if key in node:
                result[key] = canonical(node[key])
        if "members" in node:
            result["members"] = members(node["members"])
        return result

    def members(items):
        return [
            {key: value for key, value in item.items() if key not in ("astId", "contract", "type")}
            | {"type": canonical(item["type"])}
            for item in items
        ]

    return members(layout["storage"])


def normalized_abi(abi):
    # Forge reorders entries. preserve every entry and field, including duplicates.
    return sorted(json.dumps(entry, sort_keys=True) for entry in abi)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt", type=Path, help="new directory for this run; never overwritten")
    parser.add_argument("--solc", type=Path, default=Path.home() / ".local/share/svm/0.8.25/solc-0.8.25")
    parser.add_argument("--runs", type=int, default=44)
    parser.add_argument("--details", type=json.loads, help="standard JSON optimizer.details object")
    parser.add_argument("--forge-reference", type=Path, help="require exact bytecode/ABI/layout matches")
    parser.add_argument("--reference", type=Path, help="compare against another runner receipt")
    args = parser.parse_args()
    args.receipt.mkdir(parents=True, exist_ok=False)

    def save(name, obj):
        (args.receipt / name).write_text(json.dumps(obj, indent=2) + "\n")

    optimizer = {"enabled": True, "runs": args.runs}
    if args.details is not None:
        optimizer["details"] = args.details
    compiler_input = {
        "language": "Solidity",
        "sources": sources(),
        "settings": {
            "remappings": REMAPPINGS,
            "optimizer": optimizer,
            "metadata": {"useLiteralContent": False, "bytecodeHash": "none", "appendCBOR": False},
            "evmVersion": "cancun",
            "viaIR": True,
            "libraries": {},
            "outputSelection": {
                path: {name: ["abi", "evm.bytecode", "evm.deployedBytecode", "storageLayout", "irOptimized"]}
                for name, path in TARGETS.items()
            },
        },
    }
    save("input.json", compiler_input)
    record = {
        "head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "compiler": subprocess.check_output([str(args.solc), "--version"], text=True).strip(),
        "compiler_sha256": hashlib.sha256(args.solc.read_bytes()).hexdigest(),
        "started": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "settings": compiler_input["settings"],
        "source_sha256": {
            path: hashlib.sha256(source["content"].encode()).hexdigest()
            for path, source in compiler_input["sources"].items()
        },
    }
    save("receipt.json", record)
    with (args.receipt / "input.json").open() as stdin, (args.receipt / "output.json").open("w") as stdout, (args.receipt / "stderr.log").open("w") as stderr:
        result = subprocess.run([str(args.solc), "--standard-json"], cwd=ROOT, stdin=stdin, stdout=stdout, stderr=stderr)
    record["completed"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    record["exit_code"] = result.returncode
    save("receipt.json", record)
    result.check_returncode()
    output = json.loads((args.receipt / "output.json").read_text())
    errors = [item for item in output.get("errors", []) if item["severity"] == "error"]
    if errors:
        raise SystemExit("\n".join(error["formattedMessage"] for error in errors))
    reference = json.loads((args.reference / "output.json").read_text()) if args.reference else None
    rows = []
    for name, path in TARGETS.items():
        artifact = output["contracts"][path][name]
        evm = artifact["evm"]
        row = {"contract": name, "creation": len(evm["bytecode"]["object"]) // 2, "runtime": len(evm["deployedBytecode"]["object"]) // 2}
        row["stored_headroom"] = 24575 - row["creation"]
        if args.forge_reference:
            forge = json.loads((args.forge_reference / Path(path).name / (name + ".json")).read_text())
            for field in ("bytecode", "deployedBytecode"):
                assert evm[field]["object"] == forge[field]["object"].removeprefix("0x"), (name, field)
            assert normalized_abi(artifact["abi"]) == normalized_abi(forge["abi"]), (name, "ABI")
            assert normalized_layout(artifact["storageLayout"]) == normalized_layout(forge["storageLayout"]), (name, "layout")
            row["exact_forge_match"] = True
        if reference:
            previous = reference["contracts"][path][name]
            row["abi_unchanged"] = normalized_abi(artifact["abi"]) == normalized_abi(previous["abi"])
            row["layout_unchanged"] = normalized_layout(artifact["storageLayout"]) == normalized_layout(previous["storageLayout"])
            row["creation_saved"] = len(previous["evm"]["bytecode"]["object"]) // 2 - row["creation"]
            row["runtime_saved"] = len(previous["evm"]["deployedBytecode"]["object"]) // 2 - row["runtime"]
        rows.append(row)
    save("sizes.json", rows)
    print(json.dumps(rows, indent=2), flush=True)


if __name__ == "__main__":
    main()
