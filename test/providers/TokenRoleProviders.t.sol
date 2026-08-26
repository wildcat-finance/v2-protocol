// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { IRoleProvider } from 'src/access/IRoleProvider.sol';
import { ERC20RoleProvider } from 'src/providers/ERC20RoleProvider.sol';
import { IERC20RoleProvider } from 'src/providers/IERC20RoleProvider.sol';
import { ERC721RoleProvider } from 'src/providers/ERC721RoleProvider.sol';
import { IERC721RoleProvider } from 'src/providers/IERC721RoleProvider.sol';
import { ERC1155RoleProvider } from 'src/providers/ERC1155RoleProvider.sol';
import { IERC1155RoleProvider } from 'src/providers/IERC1155RoleProvider.sol';
import { ERC4626AssetsRoleProvider } from 'src/providers/ERC4626AssetsRoleProvider.sol';
import { IERC4626AssetsRoleProvider } from 'src/providers/IERC4626AssetsRoleProvider.sol';
import { ERC5192RoleProvider } from 'src/providers/ERC5192RoleProvider.sol';
import { ERC5484RoleProvider } from 'src/providers/ERC5484RoleProvider.sol';
import { RoleProviderTokenMock } from '../mocks/RoleProviderTokenMock.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract TokenRoleProvidersTest is TestKernel {
  address internal constant Holder = address(0xA11CE);
  address internal constant Recipient = address(0xB0B);
  uint8 internal constant AllStandards = type(uint8).max;

  RoleProviderTokenMock internal token;

  function setUp() external {
    vm.warp(1_714_737_030);
    token = RoleProviderTokenMock(
      _deployCode('test/mocks/RoleProviderTokenMock.sol:RoleProviderTokenMock')
    );
  }

  function _deployERC20(
    address tokenAddress,
    uint256 minimum
  ) internal returns (ERC20RoleProvider) {
    return
      ERC20RoleProvider(
        _deployCode(
          'src/providers/ERC20RoleProvider.sol:ERC20RoleProvider',
          abi.encode(tokenAddress, minimum)
        )
      );
  }

  function _deployERC721(
    address tokenAddress,
    bool skipInterfaceCheck
  ) internal returns (ERC721RoleProvider) {
    return
      ERC721RoleProvider(
        _deployCode(
          'src/providers/ERC721RoleProvider.sol:ERC721RoleProvider',
          abi.encode(tokenAddress, skipInterfaceCheck)
        )
      );
  }

  function _deployERC1155(
    address tokenAddress,
    uint256 tokenId,
    bool skipInterfaceCheck
  ) internal returns (ERC1155RoleProvider) {
    return
      ERC1155RoleProvider(
        _deployCode(
          'src/providers/ERC1155RoleProvider.sol:ERC1155RoleProvider',
          abi.encode(tokenAddress, tokenId, skipInterfaceCheck)
        )
      );
  }

  function _deployERC4626(
    address vault,
    uint256 minimum
  ) internal returns (ERC4626AssetsRoleProvider) {
    return
      ERC4626AssetsRoleProvider(
        _deployCode(
          'src/providers/ERC4626AssetsRoleProvider.sol:ERC4626AssetsRoleProvider',
          abi.encode(vault, minimum)
        )
      );
  }

  function _deployERC5192(
    address tokenAddress,
    bool requireLocked,
    bool skipInterfaceCheck
  ) internal returns (ERC5192RoleProvider) {
    return
      ERC5192RoleProvider(
        _deployCode(
          'src/providers/ERC5192RoleProvider.sol:ERC5192RoleProvider',
          abi.encode(tokenAddress, requireLocked, skipInterfaceCheck)
        )
      );
  }

  function _deployERC5484(
    address tokenAddress,
    uint8 allowedBurnAuthMask,
    bool skipInterfaceCheck
  ) internal returns (ERC5484RoleProvider) {
    return
      ERC5484RoleProvider(
        _deployCode(
          'src/providers/ERC5484RoleProvider.sol:ERC5484RoleProvider',
          abi.encode(tokenAddress, allowedBurnAuthMask, skipInterfaceCheck)
        )
      );
  }

  // ========================================================================== //
  //                         Pull-provider credentials                          //
  // ========================================================================== //

  function testFuzz_erc20CredentialTracksCurrentBalance(
    uint96 balanceSeed,
    uint96 minimumSeed
  ) external {
    uint256 balance = uint256(balanceSeed);
    uint256 minimum = bound(uint256(minimumSeed), 1, balance + 1);
    token.setBalance(Holder, balance);
    ERC20RoleProvider provider = _deployERC20(address(token), minimum);
    uint32 expected = balance >= minimum ? uint32(block.timestamp) : 0;

    assertTrue(provider.isPullProvider(), 'pull provider');
    assertEq(provider.token(), address(token), 'token');
    assertEq(provider.minBalance(), minimum, 'minimum');
    assertEq(provider.getCredential(Holder), expected, 'credential');
    assertEq(provider.validateCredential(Holder, hex'deadbeef'), expected, 'validated credential');
  }

  function testFuzz_erc20ExactBoundaryAndBalanceMove(uint96 balanceSeed) external {
    uint256 balance = bound(uint256(balanceSeed), 1, type(uint96).max);
    token.setBalance(Holder, balance);
    ERC20RoleProvider exactProvider = _deployERC20(address(token), balance);
    ERC20RoleProvider aboveProvider = _deployERC20(address(token), balance + 1);

    assertEq(exactProvider.getCredential(Holder), uint32(block.timestamp), 'exact threshold');
    assertEq(aboveProvider.getCredential(Holder), 0, 'above threshold');

    token.setBalance(Holder, 0);
    token.setBalance(Recipient, balance);
    assertEq(exactProvider.getCredential(Holder), 0, 'stale credential');
    assertEq(exactProvider.getCredential(Recipient), uint32(block.timestamp), 'new credential');
  }

  function testFuzz_erc721CredentialTracksCollectionBalance(uint96 balanceSeed) external {
    uint256 balance = bound(uint256(balanceSeed), 1, type(uint96).max);
    token.setBalance(Holder, balance);
    ERC721RoleProvider provider = _deployERC721(address(token), false);

    assertTrue(provider.isPullProvider(), 'pull provider');
    assertEq(provider.token(), address(token), 'token');
    assertEq(provider.getCredential(Holder), uint32(block.timestamp), 'credential');
    assertEq(
      provider.validateCredential(Holder, hex'deadbeef'),
      uint32(block.timestamp),
      'validated credential'
    );

    token.setBalance(Holder, 0);
    token.setBalance(Recipient, balance);
    assertEq(provider.getCredential(Holder), 0, 'stale credential');
    assertEq(provider.getCredential(Recipient), uint32(block.timestamp), 'new credential');
  }

  function testFuzz_erc1155CredentialMatchesConfiguredBalance(
    uint256 tokenId,
    uint96 balanceSeed
  ) external {
    token.setBalance(Holder, tokenId, balanceSeed);
    ERC1155RoleProvider provider = _deployERC1155(address(token), tokenId, false);
    uint32 expected = balanceSeed == 0 ? 0 : uint32(block.timestamp);

    assertTrue(provider.isPullProvider(), 'pull provider');
    assertEq(provider.token(), address(token), 'token');
    assertEq(provider.tokenId(), tokenId, 'token ID');
    assertEq(provider.getCredential(Holder), expected, 'credential');
    assertEq(provider.validateCredential(Holder, hex'deadbeef'), expected, 'validated credential');
  }

  function testFuzz_erc1155CredentialMovesAndIgnoresOtherIds(
    uint256 tokenId,
    uint96 balanceSeed
  ) external {
    uint256 balance = bound(uint256(balanceSeed), 1, type(uint96).max);
    uint256 otherTokenId = tokenId ^ 1;
    token.setBalance(Holder, otherTokenId, balance);
    ERC1155RoleProvider provider = _deployERC1155(address(token), tokenId, false);
    assertEq(provider.getCredential(Holder), 0, 'other token ID');

    token.setBalance(Holder, otherTokenId, 0);
    token.setBalance(Holder, tokenId, balance);
    assertEq(provider.getCredential(Holder), uint32(block.timestamp), 'original credential');

    token.setBalance(Holder, tokenId, 0);
    token.setBalance(Recipient, tokenId, balance);
    assertEq(provider.getCredential(Holder), 0, 'stale credential');
    assertEq(provider.getCredential(Recipient), uint32(block.timestamp), 'new credential');
  }

  function testFuzz_erc4626CredentialMatchesConvertedAssets(
    uint96 sharesSeed,
    uint96 assetsPerShareSeed,
    uint96 minimumSeed
  ) external {
    uint256 shares = uint256(sharesSeed);
    uint256 assetsPerShare = bound(uint256(assetsPerShareSeed), 1, type(uint96).max);
    uint256 currentAssets = shares * assetsPerShare;
    uint256 minimum = bound(uint256(minimumSeed), 1, currentAssets + 1);
    token.setBalance(Holder, shares);
    token.setAssetsPerShare(assetsPerShare);
    ERC4626AssetsRoleProvider provider = _deployERC4626(address(token), minimum);
    uint32 expected = currentAssets >= minimum ? uint32(block.timestamp) : 0;

    assertTrue(provider.isPullProvider(), 'pull provider');
    assertEq(provider.vault(), address(token), 'vault');
    assertEq(provider.minAssets(), minimum, 'minimum');
    assertEq(provider.getCredential(Holder), expected, 'credential');
    assertEq(provider.validateCredential(Holder, hex'deadbeef'), expected, 'validated credential');
  }

  function testFuzz_erc4626ExactBoundaryAndShareMove(
    uint96 sharesSeed,
    uint96 assetsPerShareSeed
  ) external {
    uint256 shares = bound(uint256(sharesSeed), 1, type(uint96).max);
    uint256 assetsPerShare = bound(uint256(assetsPerShareSeed), 1, type(uint96).max);
    uint256 currentAssets = shares * assetsPerShare;
    token.setBalance(Holder, shares);
    token.setAssetsPerShare(assetsPerShare);
    ERC4626AssetsRoleProvider exactProvider = _deployERC4626(address(token), currentAssets);
    ERC4626AssetsRoleProvider aboveProvider = _deployERC4626(address(token), currentAssets + 1);

    assertEq(exactProvider.getCredential(Holder), uint32(block.timestamp), 'exact threshold');
    assertEq(aboveProvider.getCredential(Holder), 0, 'above threshold');

    token.setBalance(Holder, 0);
    token.setBalance(Recipient, shares);
    assertEq(exactProvider.getCredential(Holder), 0, 'stale credential');
    assertEq(exactProvider.getCredential(Recipient), uint32(block.timestamp), 'new credential');
  }

  function test_erc4626ZeroShareBalanceSkipsConversion() external {
    token.setBalance(Holder, 0);
    token.setReadReverts(false, true, false, false, false);
    ERC4626AssetsRoleProvider provider = _deployERC4626(address(token), 1);
    assertEq(provider.getCredential(Holder), 0, 'credential');
  }

  // ========================================================================== //
  //                          Push-provider credentials                         //
  // ========================================================================== //

  function testFuzz_erc5192CredentialFollowsOwnershipAndLock(
    uint256 tokenId,
    bool requireLocked
  ) external {
    token.setOwner(tokenId, Holder);
    token.setLocked(tokenId, true);
    ERC5192RoleProvider provider = _deployERC5192(address(token), requireLocked, false);

    assertFalse(provider.isPullProvider(), 'push provider');
    assertEq(provider.token(), address(token), 'token');
    assertEq(provider.requireLocked(), requireLocked, 'locked setting');
    assertEq(provider.getCredential(Holder), 0, 'pull credential');
    assertEq(
      provider.validateCredential(Holder, abi.encode(tokenId)),
      uint32(block.timestamp),
      'owner credential'
    );

    token.setOwner(tokenId, Recipient);
    assertEq(provider.validateCredential(Holder, abi.encode(tokenId)), 0, 'stale owner');
    assertEq(
      provider.validateCredential(Recipient, abi.encode(tokenId)),
      uint32(block.timestamp),
      'new owner'
    );
  }

  function test_erc5192LockedRequirementIsOptional() external {
    uint256 tokenId = 1;
    token.setOwner(tokenId, Holder);
    token.setLocked(tokenId, false);
    ERC5192RoleProvider lockedProvider = _deployERC5192(address(token), true, false);
    ERC5192RoleProvider openProvider = _deployERC5192(address(token), false, false);

    assertEq(lockedProvider.validateCredential(Holder, abi.encode(tokenId)), 0, 'locked provider');
    assertEq(
      openProvider.validateCredential(Holder, abi.encode(tokenId)),
      uint32(block.timestamp),
      'open provider'
    );
  }

  function test_erc5192MalformedDataAndTokenReadFailuresFailClosed() external {
    uint256 tokenId = 1;
    token.setOwner(tokenId, Holder);
    token.setLocked(tokenId, true);
    ERC5192RoleProvider provider = _deployERC5192(address(token), true, false);

    assertEq(provider.validateCredential(Holder, hex'01'), 0, 'short data');
    assertEq(provider.validateCredential(Holder, abi.encode(tokenId, tokenId)), 0, 'long data');
    assertEq(provider.validateCredential(Holder, abi.encode(tokenId + 1)), 0, 'missing token');

    token.setReadReverts(false, false, true, false, false);
    assertEq(provider.validateCredential(Holder, abi.encode(tokenId)), 0, 'owner revert');
    token.setReadReverts(false, false, false, true, false);
    assertEq(provider.validateCredential(Holder, abi.encode(tokenId)), 0, 'locked revert');
  }

  function testFuzz_erc5484CredentialMatchesAllowedBurnAuthorization(
    uint256 tokenId,
    uint8 maskSeed,
    uint8 authorizationSeed
  ) external {
    uint8 mask = uint8(bound(uint256(maskSeed), 1, 0x0f));
    uint8 authorization = uint8(bound(uint256(authorizationSeed), 0, 3));
    token.setOwner(tokenId, Holder);
    token.setBurnAuth(tokenId, authorization);
    ERC5484RoleProvider provider = _deployERC5484(address(token), mask, false);
    uint32 expected = mask & (uint8(1) << authorization) != 0 ? uint32(block.timestamp) : 0;

    assertFalse(provider.isPullProvider(), 'push provider');
    assertEq(provider.token(), address(token), 'token');
    assertEq(provider.allowedBurnAuthMask(), mask, 'burn authorization mask');
    assertEq(provider.getCredential(Holder), 0, 'pull credential');
    assertEq(provider.validateCredential(Holder, abi.encode(tokenId)), expected, 'credential');
  }

  function test_erc5484CredentialFollowsOwnership() external {
    uint256 tokenId = 1;
    token.setOwner(tokenId, Holder);
    token.setBurnAuth(tokenId, 0);
    ERC5484RoleProvider provider = _deployERC5484(address(token), 1, false);

    assertEq(
      provider.validateCredential(Holder, abi.encode(tokenId)),
      uint32(block.timestamp),
      'owner credential'
    );
    token.setOwner(tokenId, Recipient);
    assertEq(provider.validateCredential(Holder, abi.encode(tokenId)), 0, 'stale owner');
    assertEq(
      provider.validateCredential(Recipient, abi.encode(tokenId)),
      uint32(block.timestamp),
      'new owner'
    );
  }

  function test_erc5484MalformedUndefinedAndReadFailuresFailClosed() external {
    uint256 tokenId = 1;
    token.setOwner(tokenId, Holder);
    token.setBurnAuth(tokenId, 0);
    ERC5484RoleProvider provider = _deployERC5484(address(token), 1, false);

    assertEq(provider.validateCredential(Holder, hex'01'), 0, 'short data');
    assertEq(provider.validateCredential(Holder, abi.encode(tokenId, tokenId)), 0, 'long data');
    assertEq(provider.validateCredential(Holder, abi.encode(tokenId + 1)), 0, 'missing token');

    token.setBurnAuth(tokenId, 4);
    assertEq(provider.validateCredential(Holder, abi.encode(tokenId)), 0, 'undefined burn auth');
    token.setReadReverts(false, false, true, false, false);
    assertEq(provider.validateCredential(Holder, abi.encode(tokenId)), 0, 'owner revert');
    token.setReadReverts(false, false, false, false, true);
    assertEq(provider.validateCredential(Holder, abi.encode(tokenId)), 0, 'burn auth revert');
  }

  // ========================================================================== //
  //                              Constructor gates                             //
  // ========================================================================== //

  function test_constructorRejectsAddressesWithoutCode() external {
    vm.expectRevert(IERC20RoleProvider.InvalidTokenAddress.selector);
    _deployERC20(address(0), 1);
    vm.expectRevert(IERC721RoleProvider.InvalidTokenAddress.selector);
    _deployERC721(address(0), false);
    vm.expectRevert(IERC1155RoleProvider.InvalidTokenAddress.selector);
    _deployERC1155(address(0), 1, false);
    vm.expectRevert(IERC4626AssetsRoleProvider.InvalidVaultAddress.selector);
    _deployERC4626(address(0), 1);
    vm.expectRevert(ERC5192RoleProvider.InvalidTokenAddress.selector);
    _deployERC5192(address(0), true, false);
    vm.expectRevert(ERC5484RoleProvider.InvalidTokenAddress.selector);
    _deployERC5484(address(0), 1, false);
  }

  function test_constructorRejectsZeroMinimums() external {
    vm.expectRevert(IERC20RoleProvider.InvalidMinimumBalance.selector);
    _deployERC20(address(token), 0);
    vm.expectRevert(IERC4626AssetsRoleProvider.InvalidMinimumAssets.selector);
    _deployERC4626(address(token), 0);
  }

  function test_constructorRejectsMissingTokenInterfaces() external {
    token.setInterfaceBehavior(0, true, false, false);
    _expectInterfaceConstructorReverts();
  }

  function test_constructorRejectsInvalidERC165Implementations() external {
    token.setInterfaceBehavior(AllStandards, true, true, false);
    _expectInterfaceConstructorReverts();
  }

  function test_constructorFailsClosedWhenInterfaceReadReverts() external {
    token.setInterfaceBehavior(AllStandards, true, false, true);
    _expectInterfaceConstructorReverts();
  }

  function _expectInterfaceConstructorReverts() internal {
    vm.expectRevert(IERC721RoleProvider.InvalidERC721.selector);
    _deployERC721(address(token), false);
    vm.expectRevert(IERC1155RoleProvider.InvalidERC1155.selector);
    _deployERC1155(address(token), 1, false);
    vm.expectRevert(ERC5192RoleProvider.InvalidERC5192.selector);
    _deployERC5192(address(token), true, false);
    vm.expectRevert(ERC5484RoleProvider.InvalidERC5484.selector);
    _deployERC5484(address(token), 1, false);
  }

  function test_skippingInterfaceChecksCreatesUsableProviders() external {
    uint256 tokenId = 1;
    token.setInterfaceBehavior(0, false, false, true);
    token.setBalance(Holder, 1);
    token.setBalance(Holder, tokenId, 1);
    token.setOwner(tokenId, Holder);
    token.setLocked(tokenId, true);
    token.setBurnAuth(tokenId, 0);

    ERC721RoleProvider erc721 = _deployERC721(address(token), true);
    ERC1155RoleProvider erc1155 = _deployERC1155(address(token), tokenId, true);
    ERC5192RoleProvider erc5192 = _deployERC5192(address(token), true, true);
    ERC5484RoleProvider erc5484 = _deployERC5484(address(token), 1, true);

    assertEq(erc721.getCredential(Holder), uint32(block.timestamp), 'ERC721 credential');
    assertEq(erc1155.getCredential(Holder), uint32(block.timestamp), 'ERC1155 credential');
    assertEq(
      erc5192.validateCredential(Holder, abi.encode(tokenId)),
      uint32(block.timestamp),
      'ERC5192 credential'
    );
    assertEq(
      erc5484.validateCredential(Holder, abi.encode(tokenId)),
      uint32(block.timestamp),
      'ERC5484 credential'
    );
  }

  function test_erc5484ConstructorRejectsInvalidBurnAuthMasks() external {
    vm.expectRevert(ERC5484RoleProvider.InvalidBurnAuthMask.selector);
    _deployERC5484(address(token), 0, false);
    vm.expectRevert(ERC5484RoleProvider.InvalidBurnAuthMask.selector);
    _deployERC5484(address(token), 0x10, false);
  }
}
