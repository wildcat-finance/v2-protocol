# Role Providers

This document captures current provider choices and future candidates.

## Current
- ERC721RoleProvider: gates on `balanceOf(lender) > 0` for a configured ERC721.
  - `skipInterfaceCheck` can be used for ERC165-less collections.
- ERC5192/5484: ERC721-compatible for balance-based gating. "Locked/soulbound" is token/contract-specific and not enforced by default.
- ERC1155RoleProvider: gates on `balanceOf(lender, tokenId) > 0` for a configured ERC1155.
  - `skipInterfaceCheck` can be used for ERC165-less collections.
- MerkleRoleProvider: validates `keccak256(abi.encode(lender))` using a sorted-pair proof from `hooksData`.
  - Root is mutable via `updateRoot` for the configured admin.

## TODO
### ERC4907 (rentable ERC721)
- Motivation: allow renters via `userOf(tokenId)` rather than owners.
- TokenId-specific; options:
  - Immutable tokenId in provider constructor.
  - Push-style provider where `hooksData` includes tokenId.
  - Allowlist or Merkle root of tokenIds.
- Credential check: `userOf(tokenId) == lender` and `userExpires(tokenId)` is 0 or in the future.
- TTL: keep at 0/short since AccessControlHooks caches "granted at", not expiry.

### ERC6551 (token-bound accounts)
- Motivation: allow token-bound accounts (TBA) as lenders.
- Two models:
  - Lender is the TBA; verify `IERC6551Account(lender).token()` and/or `owner()`.
  - Lender is EOA; compute expected TBA from registry + implementation + tokenId.
- Requires tokenId specificity unless gating on "any token in collection".
- Provider config likely needs registry + implementation + token contract (+ optional salt).
- TTL: keep at 0/short because ownership changes on transfer.

### ERC5192 / ERC5484 (soulbound)
- Base gating is the same as ERC721.
- Optional checks if we want "must be locked":
  - `locked(tokenId)` for ERC5192.
  - burn/issuer rules for ERC5484.
- TokenId-specific.

## Notes
- ERC721A/721C are implementation variants; ERC721RoleProvider already works.
- CryptoPunks-style tokens may not implement ERC165; use `skipInterfaceCheck`.
