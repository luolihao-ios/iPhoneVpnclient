# Hysteria2 跨平台订阅支持设计

## 目标

让 Forge VPN 在 Windows、Android 和 iOS 上导入 Clash YAML 或 sing-box JSON 中的 Hysteria2 节点，并生成可由三端现有 sing-box/libbox 核心直接使用的 `hysteria2` 出站配置。

## 现状与原因

订阅地址 `https://UHvvhl.subxly.cfd:8443/api/v1/client/...` 返回 HTTP 200 的 Clash YAML。YAML 的 `proxies` 列表包含 18 个 `type: hysteria2` 节点。当前解析器可读取 YAML，但 `NodeType`、`VpnNode` 和 `_normalizeJsonNode` 没有 Hysteria2 分支，因此所有节点被过滤，导入结果为零。

## 方案

### 共享节点模型

新增 `NodeType.hysteria2`，界面标签为 `Hysteria2`。`VpnNode` 增加仅用于 Hysteria2 的字段：

- `obfs`：可选混淆密码；
- `alpn`：可选 ALPN 字符串列表；
- `upMbps`、`downMbps`：可选上、下行带宽；

节点可用的最低条件是服务器、端口、密码齐全。TLS 默认启用；SNI 默认为服务器地址；`skip-cert-verify` 映射到现有 `insecure`。

### 订阅解析

Clash YAML 和 JSON 均经 `_normalizeJsonNode` 进入同一 Hysteria2 分支。支持字段：

| Clash / JSON 字段 | Forge 节点字段 |
| --- | --- |
| `type: hysteria2` | `NodeType.hysteria2` |
| `server` / `address` | `server` |
| `port` / `server_port` | `port` |
| `password` | `password` |
| `sni` / `serverName` | `serverName` |
| `alpn`（列表或字符串） | `alpn` |
| `skip-cert-verify` / `insecure` | `insecure` |
| `obfs` | `obfs` |
| `up` / `up_mbps` | `upMbps` |
| `down` / `down_mbps` | `downMbps` |

未知字段忽略；单个无效节点由既有过滤机制跳过，不会使整份订阅失败。

sing-box JSON 入站的 `tls.alpn`、`tls.server_name`、`tls.insecure` 同样会被平铺后交给该分支。

### sing-box 配置

共享 `_nodeToOutbound` 新增 Hysteria2 映射，输出：

```json
{
  "type": "hysteria2",
  "tag": "proxy",
  "server": "example.com",
  "server_port": 443,
  "password": "…",
  "obfs": { "type": "salamander", "password": "…" },
  "tls": {
    "enabled": true,
    "server_name": "…",
    "insecure": false,
    "alpn": ["h3"]
  }
}
```

`up_mbps` 和 `down_mbps` 仅在订阅提供且为正数时生成。未提供 `obfs` 时不生成 `obfs` 对象。共享配置由 Windows 进程控制器与 Android/iOS libbox 调用，因而无需额外修改各平台连接流程。

## 测试与验收

1. 新增 Clash YAML Hysteria2 样例，断言所有必要字段和 ALPN/混淆/带宽被解析。
2. 新增 sing-box JSON Hysteria2 样例，断言 TLS 字段被解析。
3. 新增配置测试，断言生成原生 `hysteria2` 出站及 TLS/obfs/带宽字段。
4. 运行新增测试、既有 AnyTLS 与订阅容错测试、完整静态检查。
5. 构建 Windows、Android；iOS 由现有 GitHub Actions 交叉构建验证。

## 非目标

- 不新增 Hysteria1、TUIC 或其他协议。
- 不改变节点健康检查或路由策略。
- 不猜测或映射 Hysteria2 的非标准扩展字段。
