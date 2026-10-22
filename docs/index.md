---
layout: home

hero:
  name: Swihomo
  text: Another mihomo client for iOS & macOS
  tagline: The mihomo core runs inside a Packet Tunnel Network Extension — no separate CLI process, no system TUN interface, and no local SOCKS bridge.
  actions:
    - theme: brand
      text: Read the architecture
      link: /pages/architecture/mihomo-bridge/
    - theme: alt
      text: Get TestFlight
      link: https://testflight.apple.com/join/ayecJQT4

features:
  - title: Embedded core
    details: The mihomo core is compiled into the Packet Tunnel extension. No separate CLI process, no system TUN device, and no local SOCKS bridge.
    link: /pages/architecture/mihomo-bridge/
    linkText: Packet flow
  - title: Provider messaging
    details: The extension owns the core and the controller secret. The app reaches controller paths and core logs only through NETunnelProviderSession messages.
    link: /pages/architecture/mihomo-bridge/#controller-access
    linkText: Controller access
  - title: Native SwiftUI
    details: One universal SwiftUI app for iOS 17+ and macOS 14+, with profiles, runtime overrides, logs, and provider resource editing.
    link: https://github.com/ruattd/swihomo
    linkText: View source
  - title: Unified logs
    details: App and core events are presented together in one searchable view, with source, module, level, and timestamp for every entry.
    link: /pages/architecture/mihomo-bridge/#logs
    linkText: Logging details
---

## How it fits together

```text
SwiftUI app
    |
    | NETunnelProviderSession provider messages
    v
Packet Tunnel extension
    |
    | NEPacketTunnelFlow <-> C bridge <-> mihomo sing-tun stack (gVisor or mipstack)
    v
Embedded mihomo core
```

Profiles stay in the app's private Application Support container. The active YAML
and runtime overrides reach the extension through
`NETunnelProviderProtocol.providerConfiguration`, and the extension keeps the
core and controller secret inside its own process boundary.

Start with the [embedded bridge overview](/pages/architecture/mihomo-bridge/) for
the packet flow, controller IPC, logging, and provider resources. Build
instructions, override syntax, and the Geo database memory warning live in the
[repository README](https://github.com/ruattd/swihomo).
