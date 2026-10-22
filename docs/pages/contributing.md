---
title: Contributing
---

# Contributing

This guide is for anyone building Swihomo locally or preparing a third-party contribution. It focuses on the steps you should follow; repository automation stays in the background.

Start with [Development Setup](/development) if you have not built the project yet, and use [Project Structure](/project-structure) to find the appropriate source area.

## Start a focused change

1. Start from the current `dev` branch and create a focused branch in your fork.
2. Initialize submodules and build the core before editing:

   ```sh
   bash scripts/init-submodules.sh
   bash scripts/build-mihomo.sh
   ```

3. Follow the existing patterns in the target area. Keep unrelated formatting, generated files, and refactors out of the change.

`dev` is the integration branch for contributions. You do not need to reproduce the publishing or scheduled maintenance workflows locally.

## Make code and localization changes

- Keep app and extension responsibilities consistent with the boundaries in [Project Structure](/project-structure).
- When changing user-facing app text, update both `Swihomo/en.lproj` and `Swihomo/zh-Hans.lproj` where applicable.
- When changing documentation, update the English page in `docs/pages/` and the corresponding Simplified Chinese page in `docs/pages/zh/`.
- Edit the root `README.md` for Overview content. The docs Overview is rendered from it rather than maintained as a separate copy.

## Verify your change locally

For app, extension, or core changes:

```sh
bash scripts/build-mihomo.sh
```

Then build the shared `Swihomo` scheme in Xcode. Exercise the behavior you changed on a signed macOS host or a physical iOS device when Packet Tunnel functionality is involved; the iOS Simulator cannot run the tunnel.

For documentation changes:

```sh
pnpm --dir docs install
pnpm --dir docs build
```

Check the pages and links you changed in both locales. If documentation dependencies changed, include the updated lockfile.

## Update the core submodule

If your contribution updates `Vendor/mihomo`, regenerate the core and version file:

```sh
bash scripts/build-mihomo.sh
bash scripts/export-mihomo-version.sh
```

Commit the submodule pointer and `Swihomo/Shared/MihomoCoreVersion.swift` together. Do not commit `Vendor/MihomoCore.xcframework` or `Vendor/mihomo/.build-mihomo/`, and do not hand-edit the generated Swift file.

Maintainer-only core rebase and release scripts are not part of a normal contribution.

## Prepare a pull request

Open your pull request against `dev` and include:

- A short summary of the change and its user-visible effect.
- The local verification you actually performed.
- Screenshots or recordings for UI changes when they help review.
- Notes about submodule, generated-file, or documentation impacts when relevant.

For app changes, Build Check runs automatically for pull requests targeting `dev`. Review its result and address failures related to your change before asking for final review.

## Files to keep out of a commit

- Core XCFrameworks, build intermediates, docs output, `node_modules/`, and Xcode user data.
- Certificates, provisioning profiles, private keys, and local environment files.
- Unrelated generated changes or dependency lockfile updates.

## Related pages

- [Development Setup](/development)
- [Project Structure](/project-structure)
- [Embedded Mihomo Bridge](/mihomo-bridge)
