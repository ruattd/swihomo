---
title: 项目结构
---

# 项目结构

Swihomo 仓库包含 SwiftUI 应用、Packet Tunnel 扩展、Go mihomo submodule 和独立的 VitePress 文档站点。开始修改前，可以通过本页找到对应的源码位置。

构建命令见[开发环境](/zh/development)，提交流程见[贡献指南](/zh/contributing)。

## 仓库布局

```text
swihomo/
├── Swihomo/                    SwiftUI 应用 target
│   ├── App/                    应用入口、AppModel、菜单栏与功能视图
│   ├── Shared/                 模型、Store、配置生成与日志持久化
│   ├── Services/               隧道控制器与扩展客户端
│   ├── Assets.xcassets/        应用资源；AboutIcon 也是文档 logo 来源
│   └── *lproj/                 英文与简体中文本地化
├── PacketTunnel/               Packet Tunnel 扩展 target
│   ├── PacketTunnelProvider.swift
│   ├── MihomoCore.swift        C 桥接层的 Swift 封装
│   └── SwihomoCore.h           导出的桥接 API
├── Vendor/
│   ├── mihomo/                 包含核心与 Go 桥接层的 submodule
│   └── MihomoCore.xcframework/ 生成的静态库，Git 忽略
├── Config/                     共享 Xcode 配置
├── Swihomo.xcodeproj/          Target、共享 scheme 与 Swift Package
├── scripts/                    构建、submodule、版本与维护脚本
├── docs/                       独立的 VitePress 文档站点
└── .github/workflows/          仓库自动化
```

## 应用、扩展与核心

- `Swihomo/` 管理界面、配置与订阅、设置等状态，通过 Network Extension API 与扩展交换配置和消息。
- `PacketTunnel/` 管理隧道生命周期、内嵌核心、控制器密钥与核心日志。`MihomoCore.swift` 封装 `SwihomoCore.h` 导出的 C 接口。
- `Vendor/mihomo/` 包含 Go 核心与桥接层。`scripts/build-mihomo.sh` 将其编译为 `Vendor/MihomoCore.xcframework`，该静态库仅由扩展链接。

应用与扩展运行在独立进程中。修改数据包转发、控制器消息、配置归属或扩展日志前，请阅读[内嵌 Mihomo Bridge](/zh/mihomo-bridge)。

## 生成文件与本地文件

| 路径 | 生成方式 | 提交时的处理 |
| --- | --- | --- |
| `Vendor/MihomoCore.xcframework/` | `scripts/build-mihomo.sh` | 不要提交 |
| `Vendor/mihomo/.build-mihomo/` | 核心构建中间产物 | 不要提交 |
| `Swihomo/Shared/MihomoCoreVersion.swift` | `scripts/export-mihomo-version.sh` | Git 跟踪；核心更新后重新生成，不要手动编辑 |
| `docs/pages/public/logo-*.png` | `docs/scripts/sync-assets.mjs` | 文档 dev/build 前生成，不要提交 |
| `docs/.vitepress/cache/`、`docs/.vitepress/dist/`、`docs/node_modules/` | 文档工具 | 不要提交 |
| `DerivedData/`、`xcuserdata/`、`.swiftpm/`、`Packages/` | Xcode 与 Swift Package | 不要提交 |

证书、描述文件、私钥和本地环境文件也不应进入提交。

## 本地开发常用脚本

日常修改通常只需要：

- `scripts/init-submodules.sh`：初始化并校验项目记录的 submodule 提交。
- `scripts/build-mihomo.sh`：构建核心并组装 XCFramework。
- `scripts/export-mihomo-version.sh`：核心更新后重新生成受 Git 跟踪的版本 Swift 文件。

其他脚本用于维护或发布操作，不属于普通本地开发流程。

## 文档站点

`docs/` 拥有自己的 `package.json` 与锁文件，不属于 Xcode target。英文页面位于 `docs/pages/`，简体中文页面位于 `docs/pages/zh/`，导航和语言配置位于 `docs/.vitepress/config.mts`。

两个 Overview 页面均渲染根目录的 `README.md`，因此修改概览内容时应编辑 README。其他用户和开发者文档是普通 Markdown 页面，修改时应同步更新两种语言。

```sh
pnpm --dir docs install
pnpm --dir docs dev
pnpm --dir docs build
```

## 相关页面

- [开发环境](/zh/development)
- [贡献指南](/zh/contributing)
- [内嵌 Mihomo Bridge](/zh/mihomo-bridge)
