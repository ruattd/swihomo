---
title: 开发环境
---

# 开发环境

本页帮助你在本地 Mac 上构建 Swihomo。项目包含两个 Xcode target：SwiftUI 应用，以及链接本地构建的 mihomo 核心的 Packet Tunnel 扩展。

源码目录说明见[项目结构](/zh/project-structure)，提交流程见[贡献指南](/zh/contributing)。

## 环境要求

- Apple Silicon Mac。当前核心构建脚本与 Xcode 项目均面向 arm64。
- Xcode 26 或更高版本，以及对应的命令行工具。
- `PATH` 中可用的 Go 1.26.8。
- 支持 submodule 的 Git。
- 能够为应用和 Packet Tunnel 扩展签名，并具有所需 Network Extension 授权的 Apple Developer 团队。

项目的部署目标为 iOS 17.0 与 macOS 14.0。测试隧道功能时，请使用已签名的 macOS 主机或 iOS 真机；模拟器无法运行 Packet Tunnel。

## 获取源码

```sh
git clone --recurse-submodules https://github.com/ruattd/swihomo.git
cd swihomo
```

如果已经克隆仓库但没有初始化 submodule，运行：

```sh
bash scripts/init-submodules.sh
```

脚本成功完成后，`Vendor/mihomo` 会处于项目记录的提交。

## 构建 mihomo 核心

```sh
bash scripts/build-mihomo.sh
```

脚本会为 iOS、iOS 模拟器和 macOS 构建桥接层，并生成 `Vendor/MihomoCore.xcframework`。PacketTunnel target 的 **Build mihomo** 构建阶段也会在核心输入变化时运行该脚本，因此通常不必在每次 Xcode 构建前手动重复执行。

## 打开并运行

```sh
open Swihomo.xcodeproj
```

1. 为 `Swihomo` 与 `PacketTunnel` 两个 target 选择你的开发团队。
2. 将两个 target 的 bundle identifier 改为已注册到你团队的值。默认值分别为 `com.swihomo.client` 与 `com.swihomo.client.PacketTunnel`。
3. 构建共享的 `Swihomo` scheme，并在已签名的 macOS 主机或 iOS 真机上运行。

首次构建时，Xcode 会自动解析锁定版本的 Swift Package 依赖。

> [!IMPORTANT]
> iOS 模拟器无法运行 Packet Tunnel，请勿使用模拟器验证连接功能。

## 生成文件

- `Vendor/MihomoCore.xcframework/`：由 `scripts/build-mihomo.sh` 生成，Git 忽略。
- `Vendor/mihomo/.build-mihomo/`：核心构建的中间产物，Git 忽略。
- `Swihomo/Shared/MihomoCoreVersion.swift`：由 `scripts/export-mihomo-version.sh` 生成。该文件会被 Git 跟踪，但不应手动编辑；普通 Xcode 构建不会自动更新它。

请勿提交 XCFramework、中间构建产物、签名材料或本地环境文件。

## 更新核心

当你的改动更新核心 submodule 时，重新构建核心并生成版本文件：

```sh
git submodule update --remote --merge Vendor/mihomo
bash scripts/build-mihomo.sh
bash scripts/export-mihomo-version.sh
```

请将 submodule 指针与重新生成的 `Swihomo/Shared/MihomoCoreVersion.swift` 一起提交。版本文件用于让默认的 `ClashMeta/<version>` 订阅 User-Agent 与内嵌核心保持一致。

## 修改文档

文档站点使用独立的 pnpm/VitePress 工具链，无需 Xcode：

```sh
pnpm --dir docs install
pnpm --dir docs dev
```

提交文档改动前，请检查生产构建：

```sh
pnpm --dir docs build
```

如果修改文档依赖，请在同一改动中更新 `docs/pnpm-lock.yaml`。

## 相关页面

- [项目结构](/zh/project-structure)
- [贡献指南](/zh/contributing)
- [内嵌 Mihomo Bridge](/zh/mihomo-bridge)
