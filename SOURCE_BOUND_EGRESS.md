# Source-Bound Egress Branch Notes

This branch adds the minimum behavior needed for source-in/source-out on
single-NIC, single-gateway, multi-public-IP hosts.

## What this branch changes

1. If an inbound does not hit a custom route rule, Xray will prefer the
   outbound handler with the same tag as the inbound.
2. If `SendIP` is empty, `0.0.0.0`, or `::`, Xray will use
   `sendThrough: "origin"` by default.

## Why this is enough for V2bX

V2bX already creates one inbound and one outbound per node tag.
The missing piece was that unmatched traffic could still fall back to the
global default outbound handler instead of the node's own outbound handler.

Once unmatched traffic prefers the same-tag outbound, `sendThrough` can be
used per node just like the `jiasu9527/v2node` independent egress logic.

## Files changed

- `conf/xray.go`
- `core/xray/outbound.go`
- `core/xray/app/dispatcher/default.go`

## Optional follow-up

If you also want the proxied-listener `origin` fix from `jiasu3`, move the
Xray dependency to `github.com/jiasu9527/xray-core` after confirming API
compatibility with the current V2bX tree.

Suggested branch name:

- `feature/source-bound-egress`

## Recommended node config

```json
{
  "ListenIP": "0.0.0.0",
  "SendIP": "0.0.0.0",
  "XrayOptions": {
    "AutoSendThroughOrigin": true,
    "EnableSameTagOutbound": true
  }
}
```

If you want to force one public IP instead of using the inbound local
address, set `SendIP` to that IP directly.

## Scope

This branch targets:

- single NIC
- single default gateway
- multiple public IPs on the same host

For multi-NIC or multi-gateway hosts, policy routing is still required.
