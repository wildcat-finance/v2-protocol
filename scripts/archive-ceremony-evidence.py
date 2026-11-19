#!/usr/bin/env python3
"""Archive an already-finalized Sepolia ceremony using only retained local evidence."""

import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import zipfile


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def archive_evidence(config_path, session):
    root = Path.cwd().resolve()
    files = {}

    def retain(filename):
        relative = Path(filename)
        require(not relative.is_absolute() and ".." not in relative.parts,
                "Evidence paths must be relative to the repository")
        target = root / relative
        require(target.resolve().is_relative_to(root), "Evidence path leaves the repository")
        require(target.is_file(), f"Missing evidence: {relative.as_posix()}")
        key = relative.as_posix()
        if key not in files:
            files[key] = target.read_bytes()
        return files[key]

    def read(filename):
        return json.loads(retain(filename))

    config = read(config_path)
    release = config["release"]
    require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", release), "Invalid release label")
    require(config["network"] == "sepolia" and config["chainId"] == 11155111,
            "Evidence archiving requires a live Sepolia release")
    base = Path("deployments/sepolia")
    session = Path(session)
    require(session.parent == base / "ceremony-evidence" and
            session.name.startswith(release + "."), "Unexpected live ceremony session")

    identity = read(session / "identity.json")
    preflight = read(session / "preflight.json")
    post = read(session / "post-activation.json")
    run_state_bytes = retain(session / "run-state.json")
    run_state = json.loads(run_state_bytes)
    plan_path = base / f"plan-{release}.json"
    package_path = base / f"ceremony-{release}-eoa.json"
    plan = read(plan_path)
    package = read(package_path)
    deployments = read(base / "deployments.json")
    retain(base / "factory-inventory.json")
    retain(base / f"source-{release}.txt")
    require(retain(base / f"run-state-{release}.json") == run_state_bytes,
            "Stable run-state differs from the session evidence")

    for label, record in [("identity", identity), ("plan", plan),
                          ("preflight", preflight), ("post-activation", post)]:
        require(record.get("release") == release and record.get("network") == "sepolia"
                and record.get("chainId") == 11155111, f"Wrong ceremony in {label}")
    require(identity.get("status") == "ready" and preflight.get("status") == "green"
            and post.get("status") == "green", "Ceremony verification is incomplete")
    require(identity.get("plan") == plan_path.as_posix()
            and identity.get("package") == package_path.as_posix()
            and identity.get("planSha256") == sha256(retain(plan_path))
            and identity.get("packageDigest") == package.get("digest")
            and package["payload"]["artifacts"]["plan"]["json"].encode() == retain(plan_path),
            "Plan or locked package differs from the ceremony identity")
    require(identity.get("contractSourceCommit") == config["contractSourceCommit"],
            "Contract source differs from the ceremony identity")
    ids = {transaction["id"] for transaction in plan["transactions"]}
    require(identity.get("transactionCount") == len(ids) and set(run_state) == ids
            and all(entry.get("status") == "verified" for entry in run_state.values()),
            "Run-state is not complete for this plan")

    cold_gate = read(Path("deployments/anvil") / f"{release}-cold-gate.json")
    acceptance = read(Path("deployments/anvil") / f"{release}-accepted-rehearsal.json")
    require(cold_gate.get("status") == "green"
            and cold_gate.get("sourceCommit") == identity["sourceCommit"],
            "Cold gate differs from the ceremony source")
    require(acceptance.get("status") == "green"
            and acceptance.get("livePlanSha256") == identity["planSha256"]
            and acceptance.get("livePackageDigest") == identity["packageDigest"],
            "Accepted rehearsal differs from the live ceremony")
    reconcile = read(base / "reconcile-report.json")
    require(reconcile.get("status") == "green" and reconcile.get("network") == "sepolia"
            and reconcile.get("actualChainId") == 11155111 and not reconcile.get("errors"),
            "Inventory reconciliation is not green")

    if config.get("activationScope") == "templates":
        final_post = read(base / f"post-activation-{release}.json")
        require(final_post.get("status") == "green" and final_post.get("release") == release
                and final_post.get("network") == "sepolia" and final_post.get("chainId") == 11155111,
                "Template finalization verification is incomplete")
        handoff = read(base / f"template-update-{release}.json")
        baseline = base / f"handoff-{config['baseRelease']}.json"
        require(handoff["baseHandoff"]["path"] == baseline.as_posix()
                and handoff["baseHandoff"]["sha256"] == sha256(retain(baseline)),
                "Base handoff differs from the template update")
        for template in handoff["templates"]:
            require(deployments.get(template["deploymentKey"]) == template["address"]
                    and deployments.get(f"{template['name']}_initCodeStorage") == template["address"],
                    "Template deployment records differ from the handoff")
    else:
        handoff = read(base / f"handoff-{release}.json")
        for spec in config.get("reusedDeployments", []):
            original = read(spec["handoff"])
            old_plan = base / f"plan-{original['release']}.json"
            candidates = [record for record in handoff["releaseContracts"]
                          if record.get("reused") and
                          record.get("provenance", {}).get("handoff") == spec["handoff"] and
                          record["provenance"].get("output") == spec["output"]]
            require(len(candidates) == 1, "Reused deployment is missing from the finalized handoff")
            entry = next(transaction for transaction in read(old_plan)["transactions"]
                         if transaction.get("output") == spec["output"])
            source_records = original.get("releaseContracts", original.get("templates", []))
            record = candidates[0]
            require(any(
                source["deploymentKey"] == record["provenance"]["deploymentKey"] and
                source["forgeArtifactName"] == entry["artifactName"] and
                source["address"] == record["address"] and
                source["deployTxHash"] == record["deployTxHash"] and
                source["startBlock"] == record["startBlock"] for source in source_records),
                "Reused deployment receipt differs from its original handoff")
            require(record["provenance"]["handoffSha256"] == sha256(retain(spec["handoff"]))
                    and record["provenance"]["planSha256"] == sha256(retain(old_plan))
                    and record["provenance"]["inventoryBaselineCommit"] == config["inventoryBaselineCommit"],
                    "Reused deployment provenance differs from its source")
    require(handoff.get("release") == release and handoff.get("chain") == {
        "network": "sepolia", "chainId": 11155111,
    }, "Finalized release handoff is missing or belongs to another ceremony")

    now = datetime.datetime.now(datetime.timezone.utc)
    manifest = {
        "schemaVersion": "1.0.0",
        "release": release,
        "network": "sepolia",
        "chainId": 11155111,
        "archivedAt": now.isoformat(),
        "sourceCommit": identity["sourceCommit"],
        "contractSourceCommit": identity["contractSourceCommit"],
        "packageDigest": identity["packageDigest"],
        "session": session.as_posix(),
        "scope": "Snapshot of retained verification evidence; archiving makes no RPC calls.",
        "files": [{"path": name, "bytes": len(data), "sha256": sha256(data)}
                  for name, data in sorted(files.items())],
    }
    output = base / "ceremony-evidence" / f"wildcat-{release}-evidence-{now.strftime('%Y%m%dT%H%M%S%fZ')}.zip"
    with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(files.items()):
            archive.writestr(name, data)
        archive.writestr("manifest.json", json.dumps(manifest, indent=2) + "\n")
    checksum = sha256(output.read_bytes())
    checksum_path = Path(str(output) + ".sha256")
    # a basename remains valid when the ZIP and checksum are moved together.
    checksum_path.write_text(f"{checksum}  {output.name}\n")
    print(f"Ceremony evidence ZIP: {output.as_posix()}")
    print(f"SHA-256: {checksum}")
    print(f"Checksum file: {checksum_path.as_posix()}")
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True)
    parser.add_argument("--session", required=True)
    args = parser.parse_args()
    try:
        archive_evidence(args.config, args.session)
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f"Cannot archive ceremony evidence: {error}\n")
