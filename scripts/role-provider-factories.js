const { getAddress, isAddress, ZeroAddress, ZeroHash } = require("ethers");

const ROLE_PROVIDER_FACTORIES = [
  ["AccessList", "access-list", "ACCESS_LIST", "accessList"],
  ["Merkle", "merkle", "MERKLE", "merkle"],
  ["ERC20", "erc20", "ERC20", "erc20"],
  ["ERC721", "erc721", "ERC721", "erc721"],
  ["ERC1155", "erc1155", "ERC1155", "erc1155"],
  ["ERC4626Assets", "erc4626-assets", "ERC4626_ASSETS", "erc4626Assets"],
].map(([name, slug, providerKind, alias]) => {
  const contract = `${name}RoleProviderFactory`;
  const source = `src/providers/${contract}.sol`;
  return {
    contract,
    source,
    artifactName: `${source}:${contract}`,
    abiArtifactName: `src/providers/I${contract}.sol:I${contract}`,
    output: `${slug}-role-provider-factory`,
    providerKind,
    alias: `${alias}RoleProviderFactory`,
  };
});

const KYC_ROLE_PROVIDER = {
  contract: "KYCRoleProvider",
  source: "src/providers/KYCRoleProvider.sol",
  artifactName: "src/providers/KYCRoleProvider.sol:KYCRoleProvider",
  output: "kyc-role-provider",
};

function validateKycRoleProvider(settings) {
  const administrator = settings?.administrator;
  if (!isAddress(administrator) || administrator === ZeroAddress || getAddress(administrator) !== administrator) {
    throw new Error("Set kycRoleProvider.administrator to a nonzero checksummed address");
  }
  if (!/^0x[0-9a-f]{64}$/.test(settings.runtimeCodeHash) || settings.runtimeCodeHash === ZeroHash) {
    throw new Error("Invalid KYC runtime code hash");
  }
}

module.exports = { ROLE_PROVIDER_FACTORIES, KYC_ROLE_PROVIDER, validateKycRoleProvider };
