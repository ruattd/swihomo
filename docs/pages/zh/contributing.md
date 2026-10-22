---
title: 贡献指南
---

# 贡献指南

本页面向在本地构建 Swihomo 或准备提交第三方贡献的开发者，重点说明你应该执行的步骤，无需了解仓库发布与定时维护自动化的内部实现。

如果尚未构建项目，请先阅读[开发环境](/zh/development)；需要定位源码时，请参阅[项目结构](/zh/project-structure)。

## 开始一次聚焦的修改

1. 从最新的 `dev` 分支开始，在你的 fork 中创建一个聚焦当前任务的分支。
2. 修改前初始化 submodule 并构建核心：

   ```sh
   bash scripts/init-submodules.sh
   bash scripts/build-mihomo.sh
   ```

3. 遵循目标区域已有的实现方式，不要混入无关的格式化、生成文件或重构。

`dev` 是接收贡献的集成分支。你无需在本地复现发布或定时维护工作流。

## 修改代码与本地化

- 遵循[项目结构](/zh/project-structure)中的应用、扩展与核心职责边界。
- 修改用户可见的应用文本时，按涉及的内容同步更新 `Swihomo/en.lproj` 与 `Swihomo/zh-Hans.lproj`。
- 修改文档时，同步更新 `docs/pages/` 中的英文页面与 `docs/pages/zh/` 中对应的简体中文页面。
- Overview 内容来自根目录的 `README.md`，请直接修改 README，不要维护另一份页面副本。

## 在本地验证改动

应用、扩展或核心改动：

```sh
bash scripts/build-mihomo.sh
```

随后在 Xcode 中构建共享的 `Swihomo` scheme。涉及 Packet Tunnel 功能时，在已签名的 macOS 主机或 iOS 真机上验证你修改的行为；iOS 模拟器无法运行隧道。

文档改动：

```sh
pnpm --dir docs install
pnpm --dir docs build
```

检查两种语言中你修改的页面与链接。如果文档依赖发生变化，请同时提交更新后的锁文件。

## 更新核心 submodule

如果你的贡献更新了 `Vendor/mihomo`，请重新构建核心并生成版本文件：

```sh
bash scripts/build-mihomo.sh
bash scripts/export-mihomo-version.sh
```

将 submodule 指针与 `Swihomo/Shared/MihomoCoreVersion.swift` 一起提交。不要提交 `Vendor/MihomoCore.xcframework` 或 `Vendor/mihomo/.build-mihomo/`，也不要手动编辑生成的 Swift 文件。

维护者使用的核心变基和发布脚本不属于普通贡献流程。

## 准备 Pull Request

请向 `dev` 分支发起 Pull Request，并提供：

- 改动摘要及其对用户的影响。
- 你实际完成的本地验证。
- 有助于审查界面改动的截图或录屏。
- submodule、生成文件或文档影响的相关说明（如适用）。

应用改动的 Pull Request 以 `dev` 为目标时会自动运行 Build Check。请查看结果，并在请求最终审查前处理与你的改动相关的失败。

## 不应提交的文件

- 核心 XCFramework、构建中间产物、文档输出、`node_modules/` 和 Xcode 用户数据。
- 证书、描述文件、私钥与本地环境文件。
- 无关的生成文件变化或依赖锁文件更新。

## 相关页面

- [开发环境](/zh/development)
- [项目结构](/zh/project-structure)
- [内嵌 Mihomo Bridge](/zh/mihomo-bridge)
