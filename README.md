# Swihomo

Swihomo is a SwiftUI client foundation for iOS and macOS. It uses a Packet Tunnel Network Extension to provide system-wide routing and is designed to host mihomo through an in-process native bridge.

## Included

- iOS and macOS SwiftUI app target
- Packet Tunnel extension target with full IPv4 and IPv6 routes
- App Sandbox backed profile metadata and YAML storage
- Local YAML import and online subscription download/refresh
- Active profile switching and persisted runtime overrides
- mihomo external-controller client for proxy-group switching and delay tests
- Separate runtime override YAML, passed as the second mihomo configuration file

## Open in Xcode

1. Open `Swihomo.xcodeproj` in Xcode 15 or newer.
2. Replace `com.swihomo.client` with an identifier in your Apple Developer team.
3. Enable the `Network Extensions` capability for `PacketTunnel`, with the `Packet Tunnel Provider` entitlement.
4. Link an implementation of `MihomoCoreEngine` as described in `docs/MIHOMO_BRIDGE.md`.
5. Build and run on a device or a signed macOS host. A simulator cannot validate a production Packet Tunnel installation.

## Architecture

The app keeps profile metadata and YAML in its private Application Support container. At connection time it serializes the active YAML and override YAML into `NETunnelProviderProtocol.providerConfiguration`. The extension reads those in-memory values, applies `NEPacketTunnelNetworkSettings`, then starts the linked core without accessing an App Group container.

The controller API is bound to `127.0.0.1` and protected by a generated secret. The SwiftUI app uses that API after connection for group selection and latency checks.

## Important

The checked-in `MihomoCoreFactory` deliberately reports an error until a native core bridge is linked. iOS Network Extensions cannot safely start a bundled CLI process, so a real product must embed mihomo as an in-process library that consumes `NEPacketTunnelFlow`. This constraint is intentional, not a fallback path.
