# Clash Hysteria / AnyTLS 兼容性设计

## 目标

让 Forge VPN 完整保留并正确转换 Clash YAML 订阅中的 Hysteria 系列与 AnyTLS 节点，避免解析器悄悄减少节点数量，并在测速前向 sing-box 写入节点所需的协议配置。

## 已确认的事实与范围

- Forge `0.1.5.003` 对用户机场订阅稳定解析出 18 个节点，而 FlClash 约显示 31 个节点。
- Forge 当前可识别 `hysteria2`，但没有旧版 `hysteria` 节点类型。
- Forge 在标准化 Hysteria2 节点时丢弃了 Clash 的 `ports` 端口范围，只向 sing-box 写入一个 `server_port`。
- 用户还观察到 FlClash 可显示而 Forge 丢失的 AnyTLS 节点。Forge 虽已有 AnyTLS 分支，但必须通过导入诊断确认源节点是否到达该分支、以及被拒绝的具体原因。
- FlClash 用 Mihomo 内核直接加载 Clash 配置；Forge 会将每个支持的节点转换为 sing-box 配置。
- 两端测速目标均为 `https://www.gstatic.com/generate_204`。本次不修改测速网址或成功标准。

本次修改位于共享 Dart 解析与配置层，因此 Windows、Android 和 iOS 会得到一致行为。本轮不试图一次实现所有 Clash 代理协议。

## 设计

### 1. 保存 Hysteria 与 AnyTLS 所需数据

扩展 `VpnNode`，保存 sing-box 配置所需的源字段：

- `serverPorts`：可选的 Clash 端口范围列表，例如 `22000-27000`，标准化为 sing-box 所需的 `22000:27000`；
- `hopInterval`：可选端口跳跃间隔；
- 旧版 Hysteria 所需的认证和带宽字段；
- AnyTLS 的会话字段和 TLS 字段，兼容下划线与连字符两种 Clash 写法。

新增 `NodeType.hysteria`。所有新增字段均为可选字段，旧节点存储记录仍可正常读取。

### 2. 解析 Clash 节点时不静默丢失

`_normalizeJsonNode` 将接受 `hysteria`、`hysteria2` 和 `hy2`：

- Hysteria2 保存密码、TLS/SNI/ALPN、不安全证书标志、Salamander 混淆、带宽、`ports` / `server-ports` 与端口跳跃间隔；
- 旧版 Hysteria 保存 `auth-str` / `auth_str`、混淆、TLS/SNI/ALPN、带宽和端口范围；
- AnyTLS 兼容规范 `anytls` 类型，以及 Clash / sing-box 的 server port、SNI、不安全证书、空闲会话字段的不同键名；
- 仍保留单端口用于界面显示及不使用端口范围的配置；
- 不支持或格式损坏的节点继续跳过，但在诊断日志中统计原因，不再静默消失。

### 3. 生成合法的 sing-box 出站配置

对 Hysteria 和 Hysteria2：

- 存在 `serverPorts` 时只生成 `server_ports`，不同时生成 `server_port`，因为 sing-box 中这两个字段冲突；
- 不存在端口范围时才生成 `server_port`；
- 只有订阅提供时才生成 `hop_interval`；
- 分别生成旧版 Hysteria 与 Hysteria2 正确的认证和混淆配置结构。

共享的配置构建器仍是唯一转换入口；Windows、Android、iOS 正式连接和临时测速配置均使用这套映射。

### 4. 在组件边界加入安全的诊断记录

每次订阅解析完成后输出一条简洁诊断，包含：

- 内容字节数及短指纹；
- 按源代理类型分组的节点数；
- 按 Forge 节点类型分组的接受数量；
- 按源类型分组的跳过数量。

日志不得包含订阅地址、密码、UUID、令牌或任何代理认证数据。这样后续只需截图即可确认 Forge 与 FlClash 是否确实解析了同一类节点。

## 非目标

- 不改变测速目标和“可用”的判定标准；
- 不宣称一次实现 Mihomo 支持的全部协议；
- 不因节点能被解析就将其标记为可用。

## 测试

1. 含 `ports` 范围的 Clash Hysteria2 节点会保留标准化范围，并仅生成 `server_ports` 的 sing-box 出站配置。
2. Clash 旧版 Hysteria 节点可解析为可用的 Forge 节点，并生成带 `auth_str` 的 sing-box `hysteria` 出站配置。
3. 使用 Clash 连字符字段的 AnyTLS 节点可正确解析并生成预期 sing-box 出站配置。
4. 解析诊断会报告已接受和未支持的类型数量，且不包含任何敏感值。
5. 现有 Hysteria2、节点存储、sing-box URL 测速与订阅容错测试保持通过。
