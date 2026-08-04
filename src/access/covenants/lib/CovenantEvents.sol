// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

/**
 * @dev Events and errors shared between a covenant mixin and its external
 *      library. Declared here rather than on either side so that moving a body
 *      into a library does not change the template's ABI, and so the two do not
 *      import each other.
 */
interface ICovenantEvents {
  event CleanDownStreakStarted(address indexed market, uint256 startedAt);
  event CleanDownCredited(address indexed market, uint256 creditedAt);
  event MarketWatched(address indexed market);
  event MarketUnwatched(address indexed market);

  error CleanDownOverdue(uint256 wasDueBy);
  error InvalidCleanDownConfiguration();
  error BorrowerDelinquentOnMarket(address market);
  error NotBorrowerMarket();
  error MarketAlreadyWatched();
  error MarketNotWatched();
  error MarketNotClosed();
  error WatchListFull();
  error InvalidGateConfiguration();

  event CommitmentScheduleSet(address indexed market, uint40[] steps, uint128[] ceilings);
  error InvalidCommitmentSchedule();
  error DrawnCeilingExceeded(uint256 drawnAfter, uint256 ceiling);

  event DrawAnnounced(
    address indexed market,
    uint256 indexed nonce,
    uint256 amount,
    uint256 executableAt,
    uint256 expiresAt
  );
  event AnnouncedDrawConsumed(address indexed market, uint256 indexed nonce);
  error DrawRequiresAnnouncement(uint256 threshold);
  error AnnouncementNotFound();
  error AnnouncementNotRipe(uint256 executableAt);
  error AnnouncementExpired(uint256 expiredAt);
  error InvalidTimelockConfiguration();
  error CallerNotCovenantBorrower();
}
