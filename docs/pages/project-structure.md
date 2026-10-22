---
title: Project Structure
---

# Project Structure

Swihomo combines a SwiftUI app, a Packet Tunnel extension, a Go mihomo submodule, and an independent VitePress site. Use this map to find the area you need before making a change.

For setup commands, see [Development Setup](/development). For the contribution workflow, see [Contributing](/contributing).

## Repository layout

```text
swihomo/
├── Swihomo/                    SwiftUI app target
│   ├── App/                    App entry, AppModel, menu bar, and views
│   ├── Shared/                 Models, stores, configuration, and log persistence
│   ├── Services/               Tunnel controller and extension clients
│   ├── Assets.xcassets/        App assets; AboutIcon also feeds the docs logo
│   └── *lproj/                 English and Simplified Chinese localization
├── PacketTunnel/               Packet Tunnel extension target
│   ├── PacketTunnelProvider.swift
│   ├── MihomoCore.swift        Swift wrapper for the C bridge
│   └── SwihomoCore.h           Exported bridge API
├── Vendor/
│   ├── mihomo/                 Git submodule containing the core and Go bridge
│   └── MihomoCore.xcframework/ Generated static library, ignored by Git
├── Config/                     Shared Xcode configuration
├── Swihomo.xcodeproj/          Targets, shared scheme, and Swift packages
├── scripts/                    Build, submodule, version, and maintenance scripts
├── docs/                       Independent VitePress documentation site
└── .github/workflows/          Repository automation
```

## App, extension, and core

- `Swihomo/` owns the UI, profiles, and settings. It composes the active configuration and communicates with the extension through Network Extension APIs.
- `PacketTunnel/` owns the tunnel lifecycle, embedded core, controller secret, and core logs. `MihomoCore.swift` wraps the C interface exported by `SwihomoCore.h`.
- `Vendor/mihomo/` contains the Go core and bridge. `scripts/build-mihomo.sh` compiles it into `Vendor/MihomoCore.xcframework`, which only the extension links.

The app and extension run in separate processes. See [Embedded Mihomo Bridge](/mihomo-bridge) when changing packet flow, controller messaging, configuration ownership, or extension logging.

## Generated and local files

| Path | How it is produced | Contribution guidance |
| --- | --- | --- |
| `Vendor/MihomoCore.xcframework/` | `scripts/build-mihomo.sh` | Do not commit |
| `Vendor/mihomo/.build-mihomo/` | Core build intermediates | Do not commit |
| `Swihomo/Shared/MihomoCoreVersion.swift` | `scripts/export-mihomo-version.sh` | Tracked; regenerate after core updates, never hand-edit |
| `docs/pages/public/logo-*.png` | `docs/scripts/sync-assets.mjs` | Generated before docs dev/build; do not commit |
| `docs/.vitepress/cache/`, `docs/.vitepress/dist/`, `docs/node_modules/` | Docs tooling | Do not commit |
| `DerivedData/`, `xcuserdata/`, `.swiftpm/`, `Packages/` | Xcode and Swift packages | Do not commit |

Also keep signing certificates, provisioning profiles, private keys, and local environment files out of commits.

## Scripts for local development

Most changes only need these scripts:

- `scripts/init-submodules.sh` initializes and verifies the recorded submodule commits.
- `scripts/build-mihomo.sh` builds the core and assembles the XCFramework.
- `scripts/export-mihomo-version.sh` regenerates the tracked core-version Swift file after a core update.

Other scripts support maintainer or release operations and are not required for a normal local development loop.

## Documentation site

`docs/` has its own `package.json` and lockfile and is not an Xcode target. English pages live in `docs/pages/`; Simplified Chinese pages live in `docs/pages/zh/`. Navigation and locale configuration are in `docs/.vitepress/config.mts`.

The Overview pages render the root `README.md`, so edit that file when changing overview content. Other user and developer guides are ordinary Markdown pages and should be updated in both locales.

```sh
pnpm --dir docs install
pnpm --dir docs dev
pnpm --dir docs build
```

## Related pages

- [Development Setup](/development)
- [Contributing](/contributing)
- [Embedded Mihomo Bridge](/mihomo-bridge)
