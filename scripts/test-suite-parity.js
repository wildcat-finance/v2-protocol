#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");

const root = path.resolve(__dirname, "..");
const legacyPath = path.join(root, "test-next/parity/legacy-suite.json");
const replacementPath = path.join(
  root,
  "test-next/parity/replacement-suite.json"
);
const outputPath = path.join(
  root,
  "test-next/parity/legacy-property-dispositions.json"
);

const families = {
  "libraries-types": {
    disposition: "direct-or-composed",
    ledger: "test-next/parity/libraries-types.md",
    intent:
      "Pure library arithmetic, packed values, event encoding, metadata reads, and exact error boundaries.",
    replacementSources: [
      "test-next/libraries/FIFOQueue.t.sol",
      "test-next/libraries/FeeMath.t.sol",
      "test-next/libraries/LibERC20.t.sol",
      "test-next/libraries/LibStoredInitCode.t.sol",
      "test-next/libraries/MarketEvents.t.sol",
      "test-next/libraries/MarketState.t.sol",
      "test-next/libraries/MathUtils.t.sol",
      "test-next/libraries/SafeCastLib.t.sol",
      "test-next/libraries/StringQuery.t.sol",
      "test-next/libraries/Withdrawal.t.sol",
      "test-next/types/HooksConfig.t.sol",
      "test-next/types/RoleProvider.t.sol",
      "test-next/types/TransientBytesArray.t.sol",
    ],
  },
  "lender-status-retired": {
    disposition: "retired",
    ledger: "test-next/parity/libraries-types.md",
    intent:
      "The legacy entry made no assertion; four focused LenderStatus properties replace the missing useful coverage.",
    replacementSources: ["test-next/types/LenderStatus.t.sol"],
  },
  "logging-utility-retired": {
    disposition: "retired",
    ledger: "test-next/parity/libraries-types.md",
    intent:
      "The legacy logging/data-generation entry was not a protocol correctness property.",
    replacementSources: [],
  },
  "role-provider-factories": {
    disposition: "composed",
    ledger: "test-next/parity/role-provider-factories.md",
    intent:
      "Typed and generic provider creation, CREATE2 identity, events, validation, and hook attachment across all six factories.",
    replacementSources: ["test-next/providers/RoleProviderFactories.t.sol"],
  },
  "token-role-providers": {
    disposition: "composed",
    ledger: "test-next/parity/token-role-providers.md",
    intent:
      "Token-backed credential truth, constructor gates, TTL behavior, and production hook admission.",
    replacementSources: [
      "test-next/providers/TokenRoleProviders.t.sol",
      "test-next/providers/RoleProviderHookIntegration.t.sol",
    ],
  },
  "managed-role-providers": {
    disposition: "composed",
    ledger: "test-next/parity/managed-role-providers.md",
    intent:
      "Access-list and Merkle administration, membership/proofs, pagination, TTLs, and production hook admission.",
    replacementSources: ["test-next/providers/ManagedRoleProviders.t.sol"],
  },
  "wildcat-arch-controller": {
    disposition: "composed",
    ledger: "test-next/parity/wildcat-arch-controller.md",
    intent:
      "Registry lifecycle, enumeration, authorization, and SphereX propagation across every registered target kind.",
    replacementSources: ["test-next/root/WildcatArchController.t.sol"],
  },
  "borrower-identity-registry": {
    disposition: "direct-or-composed",
    ledger: "test-next/parity/borrower-identity-registry.md",
    intent:
      "Factory administration, account registration, principal transfer, identity resolution, and pagination.",
    replacementSources: [
      "test-next/root/WildcatBorrowerIdentityRegistry.t.sol",
    ],
  },
  "mock-arch-controller-owner": {
    disposition: "direct-or-composed",
    ledger: "test-next/parity/mock-arch-controller-owner.md",
    intent:
      "Executor administration, permissionless testnet onboarding, owner actions, legacy fee configuration, and SphereX handoff.",
    replacementSources: ["test-next/root/MockArchControllerOwner.t.sol"],
  },
  "borrower-account-origination": {
    disposition: "composed",
    ledger: "test-next/parity/borrower-account-origination.md",
    intent:
      "Borrower-account hook and market origination through both production factory types.",
    replacementSources: [
      "test-next/integration/BorrowerAccountOrigination.t.sol",
    ],
  },
  "borrower-account-compatibility": {
    disposition: "composed",
    ledger: "test-next/parity/borrower-account-compatibility.md",
    intent:
      "Operational-account execution, principal-owned policy, market lifecycles, credentialed borrowing, and account-bound salts.",
    replacementSources: [
      "test-next/integration/BorrowerAccountCompatibility.t.sol",
      "test-next/integration/BorrowerAccountOrigination.t.sol",
      "test-next/integration/Wildcat4626WrapperIntegration.t.sol",
    ],
  },
  "hooks-administrator-transfer": {
    disposition: "composed",
    ledger: "test-next/parity/hooks-administrator-transfer.md",
    intent:
      "Hook administrator association, transfer callbacks, indexes, and deployment nonces across both production factories.",
    replacementSources: [
      "test-next/integration/HooksAdministratorTransfer.t.sol",
    ],
  },
  sanctions: {
    disposition: "composed",
    ledger: "test-next/parity/sanctions.md",
    intent:
      "Sanctions reads, borrower overrides, deterministic escrow deployment, and permissionless release.",
    replacementSources: ["test-next/sanctions/Sanctions.t.sol"],
  },
  "reentrancy-guard": {
    disposition: "direct",
    ledger: "test-next/parity/reentrancy-guard.md",
    intent:
      "Ordinary guarded calls plus state-changing and view reentrancy rejection and recovery.",
    replacementSources: ["test-next/root/ReentrancyGuard.t.sol"],
  },
  "spherex-config": {
    disposition: "direct-or-composed",
    ledger: "test-next/parity/spherex-config.md",
    intent:
      "SphereX administration, engine/operator updates, sender propagation, and registered-contract disabled guards.",
    replacementSources: ["test-next/spherex/SphereXConfig.t.sol"],
  },
  "hooks-factory-templates": {
    disposition: "composed",
    ledger: "test-next/parity/hooks-factory-templates.md",
    intent:
      "Template lifecycle, hook and market CREATE2 deployment, rejection ordering, indexes, and fee propagation across both factories.",
    replacementSources: ["test-next/factories/HooksFactories.t.sol"],
  },
  "hook-dispatch": {
    disposition: "composed",
    ledger: "test-next/parity/hook-dispatch.md",
    intent:
      "Every market entrypoint's hook flag, caller, intermediate state, calldata, trailing data, and return handling.",
    replacementSources: ["test-next/integration/HookDispatch.t.sol"],
  },
  "base-access-controls": {
    disposition: "direct-or-composed",
    ledger: "test-next/parity/access-controls.md",
    intent:
      "Shared administrator, provider, credential, role, deposit-block, and transfer-recipient behavior without inherited copies.",
    replacementSources: ["test-next/access/BaseAccessControls.t.sol"],
  },
  "open-term-hooks": {
    disposition: "composed",
    ledger: "test-next/parity/open-term-hooks.md",
    intent:
      "OpenTerm construction, market configuration, access policy, minimum deposit, callback behavior, and APR delegation.",
    replacementSources: ["test-next/access/OpenTermHooks.t.sol"],
  },
  "fixed-term-hooks": {
    disposition: "composed",
    ledger: "test-next/parity/fixed-term-hooks.md",
    intent:
      "FixedTerm construction, term boundaries, configuration, access policy, APR restrictions, and early closure.",
    replacementSources: ["test-next/access/FixedTermHooks.t.sol"],
  },
  "periodic-term-hooks": {
    disposition: "composed",
    ledger: "test-next/parity/periodic-term-hooks.md",
    intent:
      "Periodic windows, configuration, access policy, APR proposal/execution/cancellation, and exact timing boundaries.",
    replacementSources: ["test-next/access/PeriodicTermHooks.t.sol"],
  },
  "market-constraint-hooks": {
    disposition: "composed",
    ledger: "test-next/parity/market-constraint-hooks.md",
    intent:
      "APR constraint bounds and the complete temporary excess-reserve-ratio state machine.",
    replacementSources: ["test-next/access/MarketConstraintHooks.t.sol"],
  },
  "market-token": {
    disposition: "composed",
    ledger: "test-next/parity/market-token.md",
    intent:
      "Market-token metadata, mint/burn, approvals, transfers, allowances, rounding, and recipient policy across hook variants.",
    replacementSources: ["test-next/market/WildcatMarket.t.sol"],
  },
  "market-base": {
    disposition: "composed",
    ledger: "test-next/parity/market-base.md",
    intent:
      "Market construction, identity layout, state reads, accrual, liquidity, fee availability, and reentrancy boundaries.",
    replacementSources: ["test-next/market/WildcatMarket.t.sol"],
  },
  "market-config": {
    disposition: "composed",
    ledger: "test-next/parity/market-config.md",
    intent:
      "Market configuration reads and mutations, authority, liquidity, sanctions, pending APR execution, and protocol-fee updates.",
    replacementSources: ["test-next/market/WildcatMarket.t.sol"],
  },
  "market-lifecycle": {
    disposition: "composed",
    ledger: "test-next/parity/market-lifecycle.md",
    intent:
      "State persistence, deposits, fees, borrowing, repayment, closure, batch-key safety, rescue, and exact indexer events.",
    replacementSources: [
      "test-next/market/WildcatMarket.t.sol",
      "test-next/integration/HookDispatch.t.sol",
      "test-next/access/OpenTermHooks.t.sol",
      "test-next/access/FixedTermHooks.t.sol",
    ],
  },
  "market-borrower-transfer": {
    disposition: "composed",
    ledger: "test-next/parity/market-borrower-transfer.md",
    intent:
      "Borrower-transfer request/accept/cancel authority, identity and sanctions revalidation, and accounting preservation.",
    replacementSources: [
      "test-next/market/WildcatMarketBorrowerTransfer.t.sol",
    ],
  },
  "market-withdrawals": {
    disposition: "composed",
    ledger: "test-next/parity/market-withdrawals.md",
    intent:
      "Normalized/scaled/full queueing, execution, sanctions escrow, unpaid processing, repayment, and batch/account views.",
    replacementSources: ["test-next/market/WildcatMarket.t.sol"],
  },
  "market-revolving": {
    disposition: "composed",
    ledger: "test-next/parity/market-revolving.md",
    intent:
      "Drawn-principal transitions, commitment/utilization economics, fees, dust, closure, and standard-market controls.",
    replacementSources: ["test-next/market/WildcatMarket.t.sol"],
  },
  "wrapper-factory": {
    disposition: "composed",
    ledger: "test-next/parity/wildcat-4626-wrapper-factory.md",
    intent:
      "Wrapper generation routing, rounding probes, CREATE2 deployment, registration, transfer policy, and executable capacity.",
    replacementSources: ["test-next/vault/Wildcat4626WrapperFactory.t.sol"],
  },
  "wrapper-core": {
    disposition: "composed",
    ledger: "test-next/parity/wildcat-4626-wrapper.md",
    intent:
      "ERC-4626 conversion/execution, capacity, allowance, sanctions, hostile reads, backing, quarantine, and sweep behavior.",
    replacementSources: ["test-next/vault/Wildcat4626Wrapper.t.sol"],
  },
  "wrapper-integration": {
    disposition: "composed",
    ledger: "test-next/parity/wildcat-4626-wrapper-integration.md",
    intent:
      "Production wrapper readiness, sanctions composition, principal namespaces, cross-market credentials, and scaled queueing.",
    replacementSources: [
      "test-next/integration/Wildcat4626WrapperIntegration.t.sol",
    ],
  },
  "market-lens": {
    disposition: "composed",
    ledger: "test-next/parity/market-lens.md",
    intent:
      "Lens facade routing, exact probe/revert boundaries, live/core reads, factory discovery, aggregation, pagination, and deduplication.",
    replacementSources: [
      "test-next/lens/MarketLensFacade.t.sol",
      "test-next/lens/MarketLensCore.t.sol",
      "test-next/lens/MarketLensAggregator.t.sol",
    ],
  },
  "market-invariants": {
    disposition: "composed",
    ledger: "test-next/parity/market-invariants.md",
    intent:
      "Stateful safety, conservation, arithmetic, sanctions, withdrawal gates, and revolving principal/economic rules across six cells.",
    replacementSources: ["test-next/invariants/MarketMatrixInvariant.t.sol"],
  },
  "withdrawal-invariants-reassigned": {
    disposition: "reassigned",
    ledger: "test-next/parity/market-invariants.md",
    intent:
      "Withdrawal-batch identity is proved more strongly by deterministic fresh-key, collision, overflow, immutability, and drain properties.",
    replacementSources: ["test-next/market/WildcatMarket.t.sol"],
  },
  "generic-erc20-invariants-retired": {
    disposition: "retired",
    ledger: "test-next/parity/market-invariants.md",
    intent:
      "The legacy handler targeted a generic MockERC20 and all generated calls reverted; Wildcat token conservation has production-specific owners.",
    replacementSources: [],
  },
  "production-matrix-scenarios": {
    disposition: "composed",
    ledger: "test-next/parity/production-matrix-scenarios.md",
    intent:
      "Production six-cell topology and deterministic lifecycle, timing, APR, minimum-deposit, rounding, and sanctions sequences.",
    replacementSources: [
      "test-next/integration/ProductionMatrixScenarios.t.sol",
    ],
  },
  "production-economics": {
    disposition: "composed",
    ledger: "test-next/parity/production-economics.md",
    intent:
      "Production-sized standard/revolving delinquency and yield-crossover economics against independent closed-form oracles.",
    replacementSources: ["test-next/integration/ProductionEconomics.t.sol"],
  },
  "production-wrapper-scenarios-reassigned": {
    disposition: "reassigned",
    ledger: "test-next/parity/production-economics.md",
    intent:
      "The large-number wrapper variants add no separate arithmetic boundary; accrued-scale execution, market-type parity, readiness, and routing stay with the focused wrapper owners.",
    replacementSources: [
      "test-next/integration/Wildcat4626WrapperIntegration.t.sol",
      "test-next/vault/Wildcat4626WrapperFactory.t.sol",
    ],
  },
};

const expectedFamilyCounts = {
  "base-access-controls": 70,
  "borrower-account-compatibility": 18,
  "borrower-account-origination": 11,
  "borrower-identity-registry": 43,
  "fixed-term-hooks": 41,
  "generic-erc20-invariants-retired": 3,
  "hook-dispatch": 18,
  "hooks-administrator-transfer": 5,
  "hooks-factory-templates": 86,
  "lender-status-retired": 1,
  "libraries-types": 153,
  "logging-utility-retired": 1,
  "managed-role-providers": 44,
  "market-base": 17,
  "market-borrower-transfer": 29,
  "market-config": 34,
  "market-constraint-hooks": 10,
  "market-invariants": 11,
  "market-lens": 74,
  "market-lifecycle": 61,
  "market-revolving": 26,
  "market-token": 20,
  "market-withdrawals": 64,
  "mock-arch-controller-owner": 17,
  "open-term-hooks": 27,
  "periodic-term-hooks": 93,
  "production-economics": 3,
  "production-matrix-scenarios": 29,
  "production-wrapper-scenarios-reassigned": 2,
  "reentrancy-guard": 3,
  "role-provider-factories": 55,
  sanctions: 24,
  "spherex-config": 14,
  "token-role-providers": 84,
  "wildcat-arch-controller": 47,
  "withdrawal-invariants-reassigned": 2,
  "wrapper-core": 160,
  "wrapper-factory": 16,
  "wrapper-integration": 22,
};

const sourceFamilies = new Map();

function assignSources(family, sources) {
  for (const source of sources) {
    if (sourceFamilies.has(source)) {
      throw new Error(`Legacy source assigned twice: ${source}`);
    }
    sourceFamilies.set(source, family);
  }
}

assignSources("libraries-types", [
  "test/libraries/FIFOQueue.t.sol",
  "test/libraries/FeeMath.t.sol",
  "test/libraries/LibERC20.t.sol",
  "test/libraries/LibStoredInitCode.t.sol",
  "test/libraries/MarketEvents.t.sol",
  "test/libraries/MarketState.t.sol",
  "test/libraries/MathUtils.t.sol",
  "test/libraries/SafeCastLib.t.sol",
  "test/libraries/StringQuery.t.sol",
  "test/libraries/Withdrawal.t.sol",
  "test/types/HooksConfig.t.sol",
  "test/types/RoleProvider.t.sol",
  "test/types/TransientBytesArray.t.sol",
]);
assignSources("lender-status-retired", ["test/types/LenderStatus.t.sol"]);
assignSources("logging-utility-retired", ["test/LogTest.sol"]);
assignSources("role-provider-factories", [
  "test/providers/ERC1155RoleProviderFactory.t.sol",
  "test/providers/ERC20RoleProviderFactory.t.sol",
  "test/providers/ERC4626AssetsRoleProviderFactory.t.sol",
  "test/providers/ERC721RoleProviderFactory.t.sol",
  "test/providers/MerkleRoleProviderFactory.t.sol",
]);
assignSources("token-role-providers", [
  "test/providers/ERC1155RoleProvider.t.sol",
  "test/providers/ERC20RoleProvider.t.sol",
  "test/providers/ERC4626AssetsRoleProvider.t.sol",
  "test/providers/ERC5192RoleProvider.t.sol",
  "test/providers/ERC5484RoleProvider.t.sol",
  "test/providers/ERC721RoleProvider.t.sol",
]);
assignSources("managed-role-providers", [
  "test/providers/AccessListRoleProvider.t.sol",
  "test/providers/AccessListRoleProviderIntegration.t.sol",
  "test/providers/MerkleRoleProvider.t.sol",
]);
assignSources("wildcat-arch-controller", [
  "test/WildcatArchController.t.sol",
  "test/WildcatArchControllerIntegration.t.sol",
]);
assignSources("borrower-identity-registry", [
  "test/WildcatBorrowerIdentityRegistry.t.sol",
]);
assignSources("mock-arch-controller-owner", [
  "test/MockArchControllerOwner.t.sol",
]);
assignSources("borrower-account-origination", [
  "test/BorrowerAccountOrigination.t.sol",
]);
assignSources("borrower-account-compatibility", [
  "test/integration/BorrowerAccountCompatibility.t.sol",
]);
assignSources("hooks-administrator-transfer", [
  "test/HooksAdministratorTransfer.t.sol",
]);
assignSources("sanctions", ["test/EscrowTest.sol", "test/SentinelTest.sol"]);
assignSources("reentrancy-guard", ["test/ReentrancyGuard.t.sol"]);
assignSources("spherex-config", ["test/spherex/SphereXConfig.t.sol"]);
assignSources("hooks-factory-templates", [
  "test/HooksFactory.t.sol",
  "test/HooksFactoryRevolving.t.sol",
]);
assignSources("hook-dispatch", ["test/HooksIntegration.t.sol"]);
assignSources("base-access-controls", ["test/access/BaseAccessControls.t.sol"]);
assignSources("open-term-hooks", ["test/access/OpenTermHooks.t.sol"]);
assignSources("fixed-term-hooks", ["test/access/FixedTermHooks.t.sol"]);
assignSources("periodic-term-hooks", ["test/access/PeriodicTermHooks.t.sol"]);
assignSources("market-token", [
  "test/helpers/BaseERC20Test.sol",
  "test/market/WildcatMarketToken.t.sol",
]);
assignSources("market-base", ["test/market/WildcatMarketBase.t.sol"]);
assignSources("market-config", ["test/market/WildcatMarketConfig.t.sol"]);
assignSources("market-lifecycle", ["test/market/WildcatMarket.t.sol"]);
assignSources("market-borrower-transfer", [
  "test/market/WildcatMarketBorrowerTransfer.t.sol",
]);
assignSources("market-withdrawals", [
  "test/market/WildcatMarketWithdrawals.t.sol",
]);
assignSources("market-revolving", [
  "test/market/WildcatMarketRevolving.t.sol",
  "test/integration/RevolvingDifferential.t.sol",
]);
assignSources("wrapper-factory", [
  "test/vault/Wildcat4626WrapperFactory.t.sol",
]);
assignSources("wrapper-core", [
  "lib/openzeppelin-contracts/lib/erc4626-tests/ERC4626.test.sol",
  "test/vault/Wildcat4626Wrapper.t.sol",
  "test/vault/Wildcat4626WrapperGuards.t.sol",
  "test/vault/Wildcat4626WrapperRounding.t.sol",
  "test/vault/Wildcat4626WrapperStandard.t.sol",
]);
assignSources("wrapper-integration", [
  "test/integration/WrappedWithdrawalScaledQueue.t.sol",
  "test/integration/WrapperReadinessScenarios.t.sol",
  "test/integration/WrapperSanctionsScenarios.t.sol",
]);
assignSources("market-lens", [
  "test/lens/MarketLens.t.sol",
  "test/lens/MarketLensMultiFactory.t.sol",
]);
assignSources("market-invariants", [
  "test/integration/MatrixInvariant.t.sol",
  "test/invariants/CAF12MarketInvariants.t.sol",
]);
assignSources("withdrawal-invariants-reassigned", [
  "test/invariants/WithdrawalBatchIdentityInvariant.t.sol",
]);
assignSources("generic-erc20-invariants-retired", ["test/InvariantTests.sol"]);
assignSources("production-matrix-scenarios", [
  "test/integration/AprGovernance.t.sol",
  "test/integration/LifecycleScenarios.t.sol",
  "test/integration/MinimumDepositScenarios.t.sol",
  "test/integration/RoundingRegressionRepro.t.sol",
  "test/integration/SanctionsScenarios.t.sol",
]);
assignSources("production-economics", [
  "test/integration/ProductionMirror.t.sol",
]);

const marketConstraintSignatures = new Set([
  "test_setAnnualInterestAndReserveRatioBips(uint16)",
  "test_setAnnualInterestAndReserveRatioBips_AnnualInterestBipsOutOfBounds()",
  "test_setAnnualInterestAndReserveRatioBips_Decrease_Cancel()",
  "test_setAnnualInterestAndReserveRatioBips_Decrease_Decrease()",
  "test_setAnnualInterestAndReserveRatioBips_Decrease_Expire()",
  "test_setAnnualInterestAndReserveRatioBips_Decrease_Increase()",
  "test_setAnnualInterestAndReserveRatioBips_Increase()",
  "test_setAnnualInterestAndReserveRatioBips_MaxReserveRatio()",
  "test_setAnnualInterestAndReserveRatioBips_OneQuarterReduction()",
  "test_setAnnualInterestAndReserveRatioBips_SlightlyAboveQuarterReduction()",
]);

function resolveFamily(property) {
  const { source, contract } = property.origin;

  if (
    source === "test/providers/AccessListRoleProvider.t.sol" &&
    contract === "AccessListRoleProviderFactoryTest"
  ) {
    return "role-provider-factories";
  }

  if (
    (source === "test/providers/ERC20RoleProvider.t.sol" &&
      contract === "ERC20RoleProviderWildcatDebtTokenTest") ||
    (source === "test/providers/ERC4626AssetsRoleProvider.t.sol" &&
      contract === "ERC4626AssetsRoleProviderWildcatWrapperTest")
  ) {
    return "wrapper-integration";
  }

  if (
    source === "test/market/WildcatMarketConfig.t.sol" &&
    marketConstraintSignatures.has(property.signature)
  ) {
    return "market-constraint-hooks";
  }

  if (source === "test/market/WildcatMarketBorrowerTransfer.t.sol") {
    const name = property.signature.slice(0, property.signature.indexOf("("));
    if (
      /Wrapper|wrapper/.test(name) ||
      name ===
        "test_samePrincipalAccountRotationPreservesLenderSanctionsOverride" ||
      name === "test_principalMigrationStartsNewLenderSanctionsNamespace"
    ) {
      return "wrapper-integration";
    }
    if (
      name ===
        "test_existingMarketEscrowRemainsReleasableAfterPrincipalMigration" ||
      name === "test_sanctionedWithdrawalUsesPrincipalNamespace"
    ) {
      return "market-withdrawals";
    }
  }

  if (source === "test/integration/ProductionMirror.t.sol") {
    const name = property.signature.slice(0, property.signature.indexOf("("));
    if (name.includes("wrapper")) {
      return "production-wrapper-scenarios-reassigned";
    }
  }

  return sourceFamilies.get(source);
}

function resolveDisposition(property, familyId, family, exactMatches) {
  if (family.disposition === "direct-or-composed") {
    return exactMatches.length > 0 ? "direct" : "composed";
  }
  if (
    familyId === "wrapper-integration" &&
    sourceFamilies.get(property.origin.source) !== "wrapper-integration"
  ) {
    return "reassigned";
  }
  if (
    familyId === "market-withdrawals" &&
    property.origin.source === "test/market/WildcatMarketBorrowerTransfer.t.sol"
  ) {
    return "reassigned";
  }
  if (
    familyId === "market-revolving" &&
    property.origin.source === "test/integration/RevolvingDifferential.t.sol"
  ) {
    return "reassigned";
  }
  if (familyId === "market-constraint-hooks") return "reassigned";
  return family.disposition;
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function stableObjectEntries(object) {
  return Object.entries(object).sort(([a], [b]) => a.localeCompare(b));
}

function collectSolidityFiles(directory, excludedPrefix) {
  const files = [];
  const visit = (current) => {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const absolute = path.join(current, entry.name);
      const relative = path.relative(root, absolute).replaceAll("\\", "/");
      if (excludedPrefix && relative.startsWith(excludedPrefix)) continue;
      if (entry.isDirectory()) visit(absolute);
      else if (entry.isFile() && entry.name.endsWith(".sol"))
        files.push(relative);
    }
  };
  visit(path.join(root, directory));
  return files.sort();
}

function hashSources(files) {
  const hash = crypto.createHash("sha256");
  for (const file of files) {
    hash.update(file);
    hash.update("\0");
    hash.update(fs.readFileSync(path.join(root, file)));
    hash.update("\0");
  }
  return hash.digest("hex");
}

function buildManifest() {
  const legacy = readJson(legacyPath);
  const replacement = readJson(replacementPath);
  const legacySources = collectSolidityFiles("test", "test/fizz/");
  for (const property of legacy.propertyGroups) {
    if (!property.origin.source.startsWith("test/")) {
      legacySources.push(property.origin.source);
    }
  }
  const uniqueLegacySources = [...new Set(legacySources)].sort();
  const replacementSources = collectSolidityFiles("test-next");
  const replacementBySource = new Map();

  for (const property of replacement.propertyGroups) {
    if (!property.origin) {
      throw new Error(
        `Replacement property has no AST origin: ${property.signature}`
      );
    }
    const list = replacementBySource.get(property.origin.source) || [];
    list.push(property);
    replacementBySource.set(property.origin.source, list);
  }

  const unusedAssignedSources = new Set(sourceFamilies.keys());
  const familyCounts = {};
  const dispositionCounts = {};
  const properties = legacy.propertyGroups.map((property) => {
    if (!property.origin) {
      throw new Error(
        `Legacy property has no AST origin: ${property.signature}`
      );
    }
    const familyId = resolveFamily(property);
    if (!familyId) {
      throw new Error(
        `No disposition for ${property.origin.source}:${property.origin.contract}:${property.signature}`
      );
    }
    const family = families[familyId];
    if (!family) throw new Error(`Unknown disposition family: ${familyId}`);
    unusedAssignedSources.delete(property.origin.source);

    const ledgerPath = path.join(root, family.ledger);
    if (!fs.existsSync(ledgerPath)) {
      throw new Error(
        `Missing parity ledger for ${familyId}: ${family.ledger}`
      );
    }

    const exactReplacementProperties = [];
    for (const source of family.replacementSources) {
      const candidates = replacementBySource.get(source);
      if (!candidates) {
        throw new Error(
          `Replacement source for ${familyId} is absent from the canonical snapshot: ${source}`
        );
      }
      for (const candidate of candidates) {
        if (candidate.signature === property.signature) {
          exactReplacementProperties.push({
            source,
            contract: candidate.origin.contract,
            signature: candidate.signature,
          });
        }
      }
    }

    const disposition = resolveDisposition(
      property,
      familyId,
      family,
      exactReplacementProperties
    );
    familyCounts[familyId] = (familyCounts[familyId] || 0) + 1;
    dispositionCounts[disposition] = (dispositionCounts[disposition] || 0) + 1;

    return {
      legacy: {
        source: property.origin.source,
        contract: property.origin.contract,
        functionId: property.origin.functionId,
        signature: property.signature,
        kind: property.kind,
        parameterized: property.parameterized,
        concreteEntries: property.concreteEntries,
      },
      disposition,
      family: familyId,
      exactReplacementProperties,
      mappingBasis:
        exactReplacementProperties.length > 0
          ? "family-ledger-and-exact-signature"
          : "family-ledger-and-documented-intent",
    };
  });

  if (legacy.propertyGroups.length !== 1438) {
    throw new Error(
      `Legacy property count changed: expected 1438, found ${legacy.propertyGroups.length}`
    );
  }
  const concreteEntries = legacy.propertyGroups.reduce(
    (total, property) => total + property.concreteEntries,
    0
  );
  if (concreteEntries !== 1797) {
    throw new Error(
      `Legacy concrete-entry count changed: expected 1797, found ${concreteEntries}`
    );
  }
  if (unusedAssignedSources.size > 0) {
    throw new Error(
      `Configured legacy sources were not present: ${[
        ...unusedAssignedSources,
      ].join(", ")}`
    );
  }
  if (replacement.totals.unknownOrigins !== 0) {
    throw new Error(
      `Replacement snapshot has ${replacement.totals.unknownOrigins} unknown AST origins`
    );
  }
  if (replacement.totals.inheritedEntries !== 0) {
    throw new Error(
      `Replacement snapshot has ${replacement.totals.inheritedEntries} inherited entries`
    );
  }
  if (
    JSON.stringify(stableObjectEntries(familyCounts)) !==
    JSON.stringify(stableObjectEntries(expectedFamilyCounts))
  ) {
    throw new Error(
      `Disposition family counts changed:\nexpected ${JSON.stringify(
        expectedFamilyCounts
      )}\nactual   ${JSON.stringify(familyCounts)}`
    );
  }

  return {
    schemaVersion: 1,
    legacySnapshot: path.relative(root, legacyPath),
    replacementSnapshot: path.relative(root, replacementPath),
    sourceTreeHashes: {
      legacySolidity: hashSources(uniqueLegacySources),
      replacementSolidity: hashSources(replacementSources),
    },
    summary: {
      legacyProperties: legacy.propertyGroups.length,
      legacyConcreteEntries: concreteEntries,
      replacementProperties: replacement.totals.entries,
      replacementSuites: replacement.totals.suites,
      replacementInheritedEntries: replacement.totals.inheritedEntries,
      dispositionCounts: Object.fromEntries(
        stableObjectEntries(dispositionCounts)
      ),
      familyCounts: Object.fromEntries(stableObjectEntries(familyCounts)),
    },
    families: Object.fromEntries(
      stableObjectEntries(families).map(([familyId, family]) => [
        familyId,
        {
          ...family,
          legacyProperties: familyCounts[familyId],
        },
      ])
    ),
    properties,
  };
}

function main() {
  const mode = process.argv[2] || "--check";
  if (mode !== "--check" && mode !== "--write") {
    throw new Error(
      "Usage: node scripts/test-suite-parity.js [--check|--write]"
    );
  }

  const encoded = `${JSON.stringify(buildManifest(), null, 2)}\n`;
  if (mode === "--write") {
    fs.writeFileSync(outputPath, encoded);
    process.stdout.write(`Wrote ${path.relative(root, outputPath)}\n`);
    return;
  }

  if (!fs.existsSync(outputPath)) {
    throw new Error(
      `${path.relative(root, outputPath)} is missing; run with --write`
    );
  }
  const current = fs.readFileSync(outputPath, "utf8");
  if (current !== encoded) {
    throw new Error(
      `${path.relative(root, outputPath)} is stale; run with --write`
    );
  }
  process.stdout.write(
    "Validated exact dispositions for 1,438 legacy properties (1,797 concrete entries).\n"
  );
}

try {
  main();
} catch (error) {
  console.error(error.stack || error.message);
  process.exit(1);
}
