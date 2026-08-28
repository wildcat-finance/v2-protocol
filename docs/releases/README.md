# Releases

These pages define source boundaries and compatibility changes between releases.
They do not attest to deployments. Current addresses, factory lifecycle, and
receipt provenance live in
[`deployments/`](../../deployments/).

Generated [contract inventories](./inventory/README.md) pin each first-party
source unit and ABI-bearing declaration to a release commit. The V2.5 inventory
will be generated after source freeze.

## V2.5

[V2.5](./v2.5.md) is the active release line.

- The final tag and source commit will be recorded after source freeze.
- The release page describes changes from V2.1.
- Current technical docs define the detailed behavior.

## V2.1

[V2.1](./v2.1.md) adds the first canonical ERC-4626 wrapper and wrapper factory.
It does not change the V2.0 core market or hook source.

- Tag: [`v2.1.0`](https://github.com/wildcat-finance/v2-protocol/tree/v2.1.0)
- Commit: `c7be4039f8f383a9dda4e45f63331c17d63f9ed9`

## V2.0

[V2.0](./v2.0.md) is the baseline for this repository's release history.

- Tag: [`v2.0.0`](https://github.com/wildcat-finance/v2-protocol/tree/v2.0.0)
- Commit: `a70f297fbd1b1ab597e0e9a3458a2d13a34b4657`

Completed external reviews are indexed in [`audits/`](../../audits/README.md).
A later tag does not extend an earlier review's source scope.
