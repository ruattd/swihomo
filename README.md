# Swihomo

Swihomo is a native SwiftUI client for iOS and macOS that runs [mihomo](https://github.com/MetaCubeX/mihomo) inside a Packet Tunnel Network Extension. The embedded core receives packets directly from `NEPacketTunnelFlow`; it does not launch a separate CLI process, create an operating-system TUN interface, or expose a local SOCKS bridge.

## Highlights

- Universal SwiftUI app for iOS 17+ and macOS 14+
- Embedded mihomo core with packet-flow, gVisor-based TUN integration
- Local YAML import and online HTTP(S) subscriptions
- Per-subscription custom `User-Agent`, persisted for both initial downloads and refreshes
- Automatic default `User-Agent` of `ClashMeta/<mihomo-version>` when no custom value is supplied
- Profile activation, Packet Tunnel lifecycle controls, and persisted profile metadata
- Proxy-group selection, group and node sorting, and latency testing through mihomo's controller API
- Editable file and HTTP proxy/rule provider resources, followed by in-core provider updates
- Basic routing, port, LAN, IPv6, DNS, and controller-secret overrides
- Custom YAML overrides with ClashParty-compatible deep-merge syntax
- Unified app and core log viewer with source, level, and text filters

## Architecture

```text
SwiftUI app
    |
    | NETunnelProviderSession provider messages
    v
Packet Tunnel extension
    |
    | NEPacketTunnelFlow <-> C bridge <-> mihomo sing-tun gVisor stack
    v
Embedded mihomo core
```

The app stores profile metadata and YAML in its private Application Support container. When a profile connects, the active YAML and runtime override envelope are passed through `NETunnelProviderProtocol.providerConfiguration`.

The extension applies the Network Extension settings, starts the core, and owns loopback controller access. The app requests controller operations, proxy ordering, core logs, and provider-resource operations through provider messages, keeping the controller secret inside the extension boundary.

More implementation details are in [Mihomo bridge documentation](https://ruattd.github.io/swihomo/pages/architecture/mihomo-bridge/).

## Repository Layout

```text
Swihomo/              SwiftUI app, shared models, and services
PacketTunnel/         Packet Tunnel extension and Swift-to-C bridge calls
Vendor/mihomo/        mihomo fork submodule, tracking ruattd/swihomo-core Alpha
Vendor/MihomoCore.xcframework/
                       Generated static XCFramework for iOS and macOS
scripts/              Core build and version-sync scripts
docs/                 Architecture and bridge documentation
```

`Vendor/MihomoCore.xcframework` is generated and intentionally ignored by Git.

## Getting Started

### Prerequisites

- Xcode 17 or newer with iOS and macOS platform support
- Go toolchain
- An Apple Developer team authorized to use the Packet Tunnel provider entitlement

### Build

```sh
git clone --recurse-submodules https://github.com/ruattd/swihomo.git
cd swihomo
bash scripts/build-mihomo-core.sh
open Swihomo.xcodeproj
```

If the repository was cloned without submodules:

```sh
git submodule update --init --recursive
bash scripts/build-mihomo-core.sh
```

The core build creates device, simulator, and macOS slices in `Vendor/MihomoCore.xcframework`. It also reads mihomo's `constant.Version` and generates `Swihomo/Shared/MihomoCoreVersion.swift`, so the default subscription `User-Agent` always matches the rebuilt core.

In Xcode, select your development team and update bundle identifiers as needed for both `Swihomo` and `PacketTunnel`. Build and test Packet Tunnel behavior on a signed macOS host or a physical iOS device; a simulator cannot validate a production Packet Tunnel installation.

## Profiles and Subscriptions

Profiles can be imported from local YAML files or downloaded from HTTP(S) subscription URLs. Online profiles can specify an optional custom `User-Agent`. The value is stored with the profile and used for its first request and every later refresh.

Leave the field empty to use `ClashMeta/<mihomo-version>`. The version is generated when `scripts/build-mihomo-core.sh` rebuilds the embedded core.

## YAML Overrides

Swihomo applies custom YAML first, then the Basic Settings panel, so basic settings always have final priority. Custom YAML is deep-merged into the active profile and supports the [ClashParty override syntax](https://clashparty.org/docs/guide/override/yaml):

- `key!` replaces an entire object
- `+key` prepends array items
- `key+` appends array items
- `<key>` escapes a literal key that starts or ends with `+`

Invalid custom YAML prevents mihomo from starting. Save overrides, then reconnect the Packet Tunnel to apply them.

## Updating mihomo

The mihomo fork is a submodule pinned to the `Alpha` branch of [ruattd/swihomo-core](https://github.com/ruattd/swihomo-core). After updating the submodule, rebuild the XCFramework before building the app:

```sh
git submodule update --remote --merge Vendor/mihomo
bash scripts/build-mihomo-core.sh
```

## Licensing

The embedded mihomo source is GPL-3.0. Any distributed build that includes it must meet the corresponding GPL source-distribution obligations.
