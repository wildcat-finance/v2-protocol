# Releases

These notes define source boundaries and compatibility changes between protocol
releases. They are not deployment attestations. Current addresses, factory
lifecycle, and receipt provenance are owned by
[`deployments/`](../../deployments/).

## V2.5

[V2.5](./v2.5.md) is the active release line. Its final tag and source commit
will be recorded after source freeze. The page describes changes from V2.1 and
routes detailed behavior to the current technical documentation.

## V2.1

[V2.1](./v2.1.md) is pinned by tag
[`v2.1.0`](https://github.com/wildcat-finance/v2-protocol/tree/v2.1.0) at commit
`c7be4039f8f383a9dda4e45f63331c17d63f9ed9`. It adds the first canonical
ERC-4626 wrapper and wrapper factory to V2.0 without changing core market or
hook source.

`aleph-v2.1.0` points to the same commit. It is an audit-corpus pin, not a
separate protocol release.

## V2.0

[V2.0](./v2.0.md) is pinned by tag
[`v2.0.0`](https://github.com/wildcat-finance/v2-protocol/tree/v2.0.0) at commit
`a70f297fbd1b1ab597e0e9a3458a2d13a34b4657`. It is the baseline for this
repository's release history.

Completed external review evidence is indexed separately in
[`audits/`](../../audits/README.md). A later tag does not extend an earlier
review's source scope.
