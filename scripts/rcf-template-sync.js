#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const {
  REGISTRATION_SIGNATURE,
  HASH_GETTER,
  requireArtifactHash,
} = require("./template-commitments");

let ethersInstance = null;

function ethers() {
  if (!ethersInstance) {
    try {
      ({ ethers: ethersInstance } = require("ethers"));
    } catch (error) {
      throw new Error(
        "Missing dependency 'ethers'. Run `yarn install` in v2-protocol before using rcf-template-sync."
      );
    }
  }
  return ethersInstance;
}

const HOOKS_FACTORY_ABI = [
  "function getHooksTemplates() view returns (address[])",
  "function getHooksTemplateDetails(address) view returns (tuple(address originationFeeAsset,uint80 originationFeeAmount,uint16 protocolFeeBips,bool exists,bool enabled,uint24 index,address feeRecipient,string name))",
  "function isHooksTemplate(address) view returns (bool)",
  `function ${REGISTRATION_SIGNATURE}`,
  `function ${HASH_GETTER}`,
  "function updateHooksTemplateFees(address,address,address,uint80,uint16)",
  "function disableHooksTemplate(address)",
];

function parseArgs(argv) {
  if (argv.length === 0 || argv.includes("--help") || argv.includes("-h")) {
    printUsage();
    process.exit(0);
  }

  const [action, ...rest] = argv;
  const args = { action };
  for (let i = 0; i < rest.length; i += 1) {
    const token = rest[i];
    if (!token.startsWith("--")) {
      throw new Error(`Unexpected argument: ${token}`);
    }
    const key = token.slice(2);
    const next = rest[i + 1];
    if (!next || next.startsWith("--")) {
      args[key] = true;
      continue;
    }
    args[key] = next;
    i += 1;
  }
  return args;
}

function printUsage() {
  console.log(`Usage:
  node scripts/rcf-template-sync.js export --rpc-url <url> --legacy-factory <address> [--output <path>] [--network <name>]
  node scripts/rcf-template-sync.js apply --rpc-url <url> --target-factory <address> (--input <path> | --legacy-factory <address>) [--private-key <hex>] [--report <path>] [--dry-run]
  node scripts/rcf-template-sync.js verify --rpc-url <url> --target-factory <address> (--input <path> | --legacy-factory <address>) [--report <path>] [--allow-extra-target]
`);
}

function chainIdToNetworkName(chainId) {
  if (chainId === 1n) return "mainnet";
  if (chainId === 11155111n) return "sepolia";
  return `chain-${chainId.toString()}`;
}

function mustGetArg(args, key, fallbackEnv) {
  const value =
    args[key] ?? (fallbackEnv ? process.env[fallbackEnv] : undefined);
  if (value === undefined || value === "") {
    throw new Error(
      `Missing required argument --${key}${
        fallbackEnv ? ` (or ${fallbackEnv})` : ""
      }`
    );
  }
  return value;
}

function ensureDirForFile(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

function writeJson(filePath, value) {
  ensureDirForFile(filePath);
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2) + "\n", "utf8");
}

function loadJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function normalizeAddress(value) {
  return ethers().getAddress(value);
}

function normalizeTemplate(templateAddress, details, initCodeHash = null) {
  return {
    hooksTemplate: normalizeAddress(templateAddress),
    name: details.name,
    feeRecipient: normalizeAddress(details.feeRecipient),
    originationFeeAsset: normalizeAddress(details.originationFeeAsset),
    originationFeeAmount: details.originationFeeAmount.toString(),
    protocolFeeBips: Number(details.protocolFeeBips),
    enabled: Boolean(details.enabled),
    initCodeHash,
  };
}

function equalTemplateDetails(a, b) {
  return diffTemplateDetails(a, b).length === 0;
}

function diffTemplateDetails(source, target) {
  const diffs = [];
  if (source.name !== target.name) diffs.push("name");
  if (
    normalizeAddress(source.feeRecipient) !==
    normalizeAddress(target.feeRecipient)
  )
    diffs.push("feeRecipient");
  if (
    normalizeAddress(source.originationFeeAsset) !==
    normalizeAddress(target.originationFeeAsset)
  ) {
    diffs.push("originationFeeAsset");
  }
  if (
    BigInt(source.originationFeeAmount) !== BigInt(target.originationFeeAmount)
  ) {
    diffs.push("originationFeeAmount");
  }
  if (Number(source.protocolFeeBips) !== Number(target.protocolFeeBips))
    diffs.push("protocolFeeBips");
  if (Boolean(source.enabled) !== Boolean(target.enabled))
    diffs.push("enabled");
  if (source.initCodeHash?.toLowerCase() !== target.initCodeHash?.toLowerCase())
    diffs.push("initCodeHash");
  return diffs;
}

async function fetchTemplates(factory, allowLegacy = false) {
  const templates = await factory.getHooksTemplates();
  const out = [];
  for (let i = 0; i < templates.length; i += 1) {
    const templateAddress = templates[i];
    const details = await factory.getHooksTemplateDetails(templateAddress);
    let hash = null;
    try {
      hash = await factory.getHooksTemplateInitCodeHash(templateAddress);
    } catch (error) {
      const absentSelector =
        (error.code === "CALL_EXCEPTION" &&
          (error.data == null || error.data === "0x")) ||
        (error.code === "BAD_DATA" && error.value === "0x");
      if (!allowLegacy || !absentSelector) throw error;
    }
    if (hash !== null) hash = requireArtifactHash(hash, templateAddress);
    out.push(normalizeTemplate(templateAddress, details, hash));
  }
  return out;
}

async function getSourceTemplates(args, provider) {
  if (args.input) {
    const payload = loadJson(args.input);
    if (!Array.isArray(payload.templates)) {
      throw new Error(`Invalid input file ${args.input}: missing templates[]`);
    }
    return payload.templates.map((template) =>
      normalizeTemplate(template.hooksTemplate, template, template.initCodeHash)
    );
  }

  const legacyFactoryAddress = mustGetArg(
    args,
    "legacy-factory",
    "LEGACY_HOOKS_FACTORY"
  );
  const legacyFactory = new (ethers().Contract)(
    normalizeAddress(legacyFactoryAddress),
    HOOKS_FACTORY_ABI,
    provider
  );
  return fetchTemplates(legacyFactory, true);
}

function requireSourceCommitments(templates) {
  // an old export needs artifact hashes added explicitly. hashing a live decoder
  // response would just approve whatever it happens to return.
  const seen = new Set();
  for (const template of templates) {
    const address = normalizeAddress(template.hooksTemplate);
    if (seen.has(address)) throw new Error(`Duplicate template ${address}`);
    seen.add(address);
    template.initCodeHash = requireArtifactHash(template.initCodeHash, address);
  }
}

async function preflightCommitments(factory, templates) {
  requireSourceCommitments(templates);
  const existing = new Map();
  // finish every commitment check before sending the first transaction.
  for (const source of templates) {
    const address = normalizeAddress(source.hooksTemplate);
    let hash;
    try {
      hash = await factory.getHooksTemplateInitCodeHash(address);
    } catch (error) {
      throw new Error(
        `Cannot read target artifact commitment for ${address}. This tool requires the new factory interface; use pinned historical tooling for old targets. ${error.message}`
      );
    }
    const exists = await factory.isHooksTemplate(address);
    if (exists && requireArtifactHash(hash, address) !== source.initCodeHash) {
      throw new Error(
        `${address}: target has a different immutable initCodeHash`
      );
    }
    existing.set(address, { exists, initCodeHash: hash });
  }
  return existing;
}

async function actionExport(args) {
  const rpcUrl = mustGetArg(args, "rpc-url", "RPC_URL");
  const legacyFactoryAddress = mustGetArg(
    args,
    "legacy-factory",
    "LEGACY_HOOKS_FACTORY"
  );
  const provider = new (ethers().JsonRpcProvider)(rpcUrl);
  const network = await provider.getNetwork();
  const networkName = args.network || chainIdToNetworkName(network.chainId);
  const outputPath =
    args.output ||
    path.join("deployments", networkName, "rcf-template-sync-export.json");

  const legacyFactory = new (ethers().Contract)(
    normalizeAddress(legacyFactoryAddress),
    HOOKS_FACTORY_ABI,
    provider
  );

  const templates = await fetchTemplates(legacyFactory, true);

  const payload = {
    schemaVersion: "1.1.0",
    generatedAt: new Date().toISOString(),
    network: networkName,
    chainId: Number(network.chainId),
    sourceFactory: normalizeAddress(legacyFactoryAddress),
    templates,
  };

  writeJson(outputPath, payload);
  console.log(`Exported ${templates.length} templates to ${outputPath}`);
}

async function actionApply(args) {
  const rpcUrl = mustGetArg(args, "rpc-url", "RPC_URL");
  const targetFactoryAddress = mustGetArg(
    args,
    "target-factory",
    "REVOLVING_HOOKS_FACTORY"
  );
  const provider = new (ethers().JsonRpcProvider)(rpcUrl);
  const network = await provider.getNetwork();
  const networkName = args.network || chainIdToNetworkName(network.chainId);
  const dryRun = Boolean(args["dry-run"]);
  const reportPath =
    args.report ||
    path.join(
      "deployments",
      networkName,
      "rcf-template-sync-apply-report.json"
    );
  const templates = await getSourceTemplates(args, provider);

  const privateKey =
    args["private-key"] ||
    process.env.DEPLOYER_PRIVATE_KEY ||
    process.env.PVT_KEY ||
    process.env.PRIVATE_KEY;

  if (!dryRun && !privateKey) {
    throw new Error(
      "Missing private key. Provide --private-key or DEPLOYER_PRIVATE_KEY/PVT_KEY/PRIVATE_KEY."
    );
  }

  const signer = dryRun
    ? provider
    : new (ethers().Wallet)(privateKey, provider);
  const targetFactory = new (ethers().Contract)(
    normalizeAddress(targetFactoryAddress),
    HOOKS_FACTORY_ABI,
    signer
  );

  const commitments = await preflightCommitments(targetFactory, templates);
  const actions = [];
  for (let i = 0; i < templates.length; i += 1) {
    const source = templates[i];
    const templateAddress = normalizeAddress(source.hooksTemplate);

    const { exists, initCodeHash } = commitments.get(templateAddress);
    if (!exists) {
      if (dryRun) {
        actions.push({
          action: "addHooksTemplate",
          hooksTemplate: templateAddress,
          txHash: null,
          dryRun: true,
        });
      } else {
        const tx = await targetFactory.addHooksTemplate(
          templateAddress,
          source.name,
          source.feeRecipient,
          source.originationFeeAsset,
          source.originationFeeAmount,
          source.protocolFeeBips,
          source.initCodeHash
        );
        const receipt = await tx.wait();
        const recorded = await targetFactory.getHooksTemplateInitCodeHash(
          templateAddress
        );
        if (
          requireArtifactHash(recorded, templateAddress) !== source.initCodeHash
        ) {
          throw new Error(
            `${templateAddress}: registered artifact hash does not match`
          );
        }
        actions.push({
          action: "addHooksTemplate",
          hooksTemplate: templateAddress,
          txHash: receipt.hash,
        });
      }

      if (!source.enabled) {
        if (dryRun) {
          actions.push({
            action: "disableHooksTemplate",
            hooksTemplate: templateAddress,
            txHash: null,
            dryRun: true,
          });
        } else {
          const tx = await targetFactory.disableHooksTemplate(templateAddress);
          const receipt = await tx.wait();
          actions.push({
            action: "disableHooksTemplate",
            hooksTemplate: templateAddress,
            txHash: receipt.hash,
          });
        }
      }
      continue;
    }

    const current = normalizeTemplate(
      templateAddress,
      await targetFactory.getHooksTemplateDetails(templateAddress),
      initCodeHash
    );

    if (
      normalizeAddress(current.feeRecipient) !==
        normalizeAddress(source.feeRecipient) ||
      normalizeAddress(current.originationFeeAsset) !==
        normalizeAddress(source.originationFeeAsset) ||
      BigInt(current.originationFeeAmount) !==
        BigInt(source.originationFeeAmount) ||
      Number(current.protocolFeeBips) !== Number(source.protocolFeeBips)
    ) {
      if (dryRun) {
        actions.push({
          action: "updateHooksTemplateFees",
          hooksTemplate: templateAddress,
          txHash: null,
          dryRun: true,
        });
      } else {
        const tx = await targetFactory.updateHooksTemplateFees(
          templateAddress,
          source.feeRecipient,
          source.originationFeeAsset,
          source.originationFeeAmount,
          source.protocolFeeBips
        );
        const receipt = await tx.wait();
        actions.push({
          action: "updateHooksTemplateFees",
          hooksTemplate: templateAddress,
          txHash: receipt.hash,
        });
      }
    }

    if (source.enabled === false && current.enabled === true) {
      if (dryRun) {
        actions.push({
          action: "disableHooksTemplate",
          hooksTemplate: templateAddress,
          txHash: null,
          dryRun: true,
        });
      } else {
        const tx = await targetFactory.disableHooksTemplate(templateAddress);
        const receipt = await tx.wait();
        actions.push({
          action: "disableHooksTemplate",
          hooksTemplate: templateAddress,
          txHash: receipt.hash,
        });
      }
    }

    if (source.enabled === true && current.enabled === false) {
      actions.push({
        action: "warning",
        hooksTemplate: templateAddress,
        message:
          "Target is disabled but source is enabled; no enable method exists.",
      });
    }

    if (source.name !== current.name) {
      actions.push({
        action: "warning",
        hooksTemplate: templateAddress,
        message: "Template name mismatch; no rename method exists.",
      });
    }
  }

  const report = {
    schemaVersion: "1.0.0",
    generatedAt: new Date().toISOString(),
    network: networkName,
    chainId: Number(network.chainId),
    targetFactory: normalizeAddress(targetFactoryAddress),
    dryRun,
    templatesProcessed: templates.length,
    actions,
  };

  writeJson(reportPath, report);
  console.log(
    `Apply complete. Actions: ${actions.length}. Report: ${reportPath}`
  );
}

async function actionVerify(args) {
  const rpcUrl = mustGetArg(args, "rpc-url", "RPC_URL");
  const targetFactoryAddress = mustGetArg(
    args,
    "target-factory",
    "REVOLVING_HOOKS_FACTORY"
  );
  const allowExtraTarget = Boolean(args["allow-extra-target"]);
  const provider = new (ethers().JsonRpcProvider)(rpcUrl);
  const network = await provider.getNetwork();
  const networkName = args.network || chainIdToNetworkName(network.chainId);
  const reportPath =
    args.report ||
    path.join(
      "deployments",
      networkName,
      "rcf-template-sync-verify-report.json"
    );

  const sourceTemplates = await getSourceTemplates(args, provider);
  requireSourceCommitments(sourceTemplates);
  const sourceByAddress = new Map();
  for (const template of sourceTemplates) {
    sourceByAddress.set(normalizeAddress(template.hooksTemplate), template);
  }

  const targetFactory = new (ethers().Contract)(
    normalizeAddress(targetFactoryAddress),
    HOOKS_FACTORY_ABI,
    provider
  );

  const targetTemplates = await fetchTemplates(targetFactory);
  const targetByAddress = new Map();
  for (const template of targetTemplates) {
    targetByAddress.set(normalizeAddress(template.hooksTemplate), template);
  }

  const missing = [];
  const mismatched = [];
  for (const [templateAddress, source] of sourceByAddress.entries()) {
    const target = targetByAddress.get(templateAddress);
    if (!target) {
      missing.push(templateAddress);
      continue;
    }
    if (!equalTemplateDetails(source, target)) {
      mismatched.push({
        hooksTemplate: templateAddress,
        fields: diffTemplateDetails(source, target),
        source,
        target,
      });
    }
  }

  const extras = [];
  if (!allowExtraTarget) {
    for (const templateAddress of targetByAddress.keys()) {
      if (!sourceByAddress.has(templateAddress)) {
        extras.push(templateAddress);
      }
    }
  }

  const ok =
    missing.length === 0 && mismatched.length === 0 && extras.length === 0;
  const report = {
    schemaVersion: "1.0.0",
    generatedAt: new Date().toISOString(),
    network: networkName,
    chainId: Number(network.chainId),
    targetFactory: normalizeAddress(targetFactoryAddress),
    sourceTemplatesCount: sourceTemplates.length,
    targetTemplatesCount: targetTemplates.length,
    allowExtraTarget,
    ok,
    missing,
    mismatched,
    extras,
  };

  writeJson(reportPath, report);
  console.log(`Verify report written to ${reportPath}`);
  if (!ok) {
    process.exit(1);
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  switch (args.action) {
    case "export":
      await actionExport(args);
      return;
    case "apply":
      await actionApply(args);
      return;
    case "verify":
      await actionVerify(args);
      return;
    default:
      throw new Error(`Unknown action: ${args.action}`);
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.message || error);
    process.exit(1);
  });
}

module.exports = {
  HOOKS_FACTORY_ABI,
  normalizeTemplate,
  diffTemplateDetails,
  fetchTemplates,
  requireSourceCommitments,
  preflightCommitments,
};
