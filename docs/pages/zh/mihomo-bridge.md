# 内嵌 Mihomo 桥接

Swihomo 从 `Alpha` 分支将 `MetaCubeX/mihomo` 引入到 `Vendor/mihomo`。
它被编译为静态库 `Vendor/MihomoCore.xcframework`，并且仅由 Packet Tunnel 扩展链接。

## 数据包流架构

该桥接层不会创建额外的系统 TUN 设备，不会访问私有 utun 文件描述符，也不通过本地 SOCKS 端口转发。

```text
NEPacketTunnelFlow <-> PacketFlowTun <-> mihomo sing-tun gVisor stack
```

Swift 通过 `readPackets` 读取原始 IPv4 与 IPv6 数据包，将复制的数据发送给 Go 桥接层，并通过 `writePackets` 写出 Go 回调的输出。

## 控制器访问

外部控制器在 Packet Tunnel 扩展进程中监听。应用使用 `NETunnelProviderSession.sendProviderMessage` 请求控制器路径；扩展执行回环 HTTP 请求并返回状态与响应体。这样可确保控制器密钥与回环连接始终局限于扩展内部。

<a id="logs"></a>

## 日志

应用在自身沙盒中记录生命周期、配置、隧道、代理与错误事件。Go 桥接层订阅 mihomo 的日志流，并通过 C 回调将每个事件发送到扩展自己的日志存储。日志界面在已连接时通过 provider 消息获取内核存储，并将两个来源一同呈现。应用与内核来源各自保留最新的 1,000 条记录。

每条记录包含来源、模块、等级与时间戳。日志界面支持关键词搜索，以及按来源和等级筛选。应用错误还会记录 Swift 错误类型、NSError domain 与 code、失败原因，以及存在时的底层错误。

## 资源

扩展在合并运行时覆盖设置后，会发现当前配置中 `proxy-providers` 与 `rule-providers` 下的 `file` 和 `http` 条目。它在 mihomo 的主目录内解析每个 provider 的缓存，并且仅通过 provider 消息向应用暴露一个不透明的资源 ID。应用可以读取、编辑或替换这些文件。随后，它通过控制器 IPC 调用 mihomo 对应的 provider 更新端点，以加载文件更改或下载最新的 HTTP 资源。内联 provider 没有对应的磁盘文件，因此被有意排除。

## 配置归属

`MihomoConfigurationBuilder` 仍负责生成配置与运行时覆盖的 YAML 数据。自定义 YAML 会先深度合并到配置中，随后应用的基础覆盖设置具有更高优先级。自定义 YAML 遵循 ClashParty 的覆盖语法：`key!` 替换整个对象，`+key` 在数组前插入，`key+` 在数组后追加，`<key>` 用于转义以 `+` 开头或结尾的键。

当桥接层安装其 packet-flow TUN 工厂时，mihomo 分支会忽略那些会创建或配置操作系统接口的配置 TUN 字段：

- `enable`、`device`、`stack`、`file-descriptor`
- 路由、接口过滤、UID 过滤、路由标记与 auto-route 选项
- `auto-route`、`auto-detect-interface`、`auto-redirect`、GSO、`recvmsgx` 与 `sendmsgx`

它改用 Network Extension 地址 `198.18.0.1/24` 与 `fd00::1/64`，使用 gVisor 栈，并且不更改主机路由。DNS 劫持、NAT 行为、超时以及所有非 TUN 的配置项仍由配置控制。

## 重新构建

更改 `Vendor/mihomo` 或 Go 桥接层后，请运行：

```sh
bash scripts/build-mihomo.sh
```

该脚本会在 `Vendor/MihomoCore.xcframework` 中生成设备、模拟器与 macOS 切片。它需要 Go、Xcode 命令行工具，以及固定版本的 mihomo 源码所声明的 Go 模块。

## 签名检查清单

- 应用和 `PacketTunnel` 都需要获批的 `packet-tunnel-provider` Network Extension 授权。
- 生产版 iOS 构建需要显式的 App ID，以及包含该授权的描述文件。
- 所链接的 mihomo 源码采用 GPL-3.0 许可。分发构建版本时必须满足其源码分发义务。
