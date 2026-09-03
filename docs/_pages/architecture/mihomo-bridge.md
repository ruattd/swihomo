---
layout: post
title: Embedded Mihomo Bridge
permalink: /pages/architecture/mihomo-bridge/
---

# Embedded Mihomo Bridge

Swihomo vendors `MetaCubeX/mihomo` from the `Alpha` branch at
`Vendor/mihomo`. It is compiled as the static `Vendor/MihomoCore.xcframework`
and linked only by the Packet Tunnel extension.

## Packet Flow Architecture

The bridge does not create another system TUN device, access a private utun
file descriptor, or forward through a local SOCKS port.

```text
NEPacketTunnelFlow <-> PacketFlowTun <-> mihomo sing-tun gVisor stack
```

Swift reads raw IPv4 and IPv6 packets through `readPackets`, sends copied data
to the Go bridge, and writes Go callback output through `writePackets`.

## Controller Access

The external controller listens in the Packet Tunnel extension process. The app
uses `NETunnelProviderSession.sendProviderMessage` to request controller paths;
the extension performs the loopback HTTP request and returns the status and
body. This keeps the controller secret and loopback connection inside the
extension boundary.

## Logs

The app records lifecycle, profile, tunnel, proxy, and error events in its own
sandbox. The Go bridge subscribes to mihomo's log stream and sends each event
through a C callback to the extension's own log store. The Logs screen fetches
the core store through provider messages while connected and presents both
sources together. App and core sources each retain their newest 1,000 entries.

Entries include source, module, level, and timestamp. The Logs screen supports
keyword search plus source and level filters. App errors additionally record
the Swift error type, NSError domain and code, failure reason, and underlying
error when present.

## Resources

The extension discovers `file` and `http` entries in the active profile's
`proxy-providers` and `rule-providers` after it merges runtime overrides. It
resolves each provider cache within mihomo's home directory and exposes only an
opaque resource ID to the app through provider messages. The app can read,
edit, or replace those files. It then calls mihomo's matching provider update
endpoint through controller IPC to load file changes or download the latest
HTTP resource. Inline providers have no backing file and are intentionally
excluded.

## Configuration Ownership

`MihomoConfigurationBuilder` continues to create the profile and runtime
override YAML data. Custom YAML is deep-merged into the profile first, then
the app's basic overrides take precedence. Custom YAML follows ClashParty's
override syntax: `key!` replaces an object, `+key` prepends an array, `key+`
appends an array, and `<key>` escapes a key that begins or ends with `+`.

When the bridge installs its packet-flow TUN factory, the mihomo fork ignores
profile TUN fields that would create or configure an operating-system interface:

- `enable`, `device`, `stack`, `file-descriptor`
- routes, interface filters, UID filters, route marks, and auto-route options
- `auto-route`, `auto-detect-interface`, `auto-redirect`, GSO, `recvmsgx`, and `sendmsgx`

It instead uses the Network Extension addresses `198.18.0.1/24` and
`fd00::1/64`, with the gVisor stack and no host routing changes. DNS hijacking,
NAT behavior, timeouts, and all non-TUN profile settings remain under the
profile's control.

## Rebuild

Run this after changing `Vendor/mihomo` or the Go bridge:

```sh
bash scripts/build-mihomo.sh
```

The script produces device, simulator, and macOS slices in
`Vendor/MihomoCore.xcframework`. It requires Go, Xcode command-line tools, and
the Go modules declared by the pinned mihomo source.

## Signing Checklist

- Both the app and `PacketTunnel` require the approved `packet-tunnel-provider` Network Extension entitlement.
- Production iOS builds need an explicit App ID and provisioning profile with that entitlement.
- The linked mihomo source is GPL-3.0. Distributed builds must meet its source-distribution obligations.
