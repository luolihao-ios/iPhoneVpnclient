# 移除三组 DoH 自动切换设计

## 背景与根因

Windows 运行日志显示，连接期间 sing-box 在执行任何远程 DNS 请求前就因默认缓存文件启动失败：

```text
FATAL start service: initialize cache-file: open cache.db: Access is denied.
```

现有连接协调器把随后发生的本地代理端口拒绝误判为 Cloudflare、Google、Quad9 不可用，并依次重启 sing-box。移动端虽然不一定遇到相同的文件权限错误，但共用的三组回退策略仍会因为代理 DoH 不兼容、启动较慢或 HTTP 204 验证失败而主动断开原本可传输流量的节点。

本次回退同时处理两个独立问题：移除跨平台三组 DoH 强制验证，并避免 Windows 使用未指定路径的默认 `cache.db`。

## 目标行为

- Windows、Android 和 iOS 都恢复为一次连接尝试。
- 平台报告连接成功后，应用保持连接，不再轮换 Cloudflare、Google、Quad9，也不再以连接后的 HTTP 204 验证决定是否强制断开。
- DNS 配置恢复到引入三组 DoH 前的简单策略：
  - 节点服务器域名使用本地 DNS；
  - 默认使用本地 DNS `223.5.5.5`；
  - 智能分流仍使用既有中国域名与中国 IP 规则集决定直连或代理；
  - 不生成三组远程 DoH 服务器和远程 DNS 选择规则。
- Windows 桌面连接不启用默认路径的 `cache.db`，避免运行目录无写入权限或多进程占用导致 sing-box 启动失败。
- 节点列表中的 HTTP 204 可用性检查保持不变；本次只删除“正式连接后的三组 DNS 回退验证”。

## 代码范围

### 删除连接协调与持久化

- `AppProvider.connect` 不再调用 `DnsFallbackCoordinator`，而是直接调用一次平台连接方法。
- 删除远程 DNS 首选项的读取、写入、轮换、取消和统一失败提示。
- 删除仅服务于该功能的依赖注入接口和测试。
- 删除不再使用的 `dns_fallback_coordinator.dart`、`connection_health.dart` 和 `remote_dns.dart`；若其他功能仍有引用，则先移除引用后再删除。

### 恢复共享 sing-box 配置

- `buildSingBoxConfig` 移除 `remoteDnsProvider` 参数。
- DNS 服务器恢复为单个本地 UDP DNS。
- DNS `final` 固定为本地解析器。
- 保留节点域名、本地 DNS、中国规则集和现有路由模式逻辑。
- 不修改 VMess、VLESS、Trojan、Shadowsocks、Hysteria2、AnyTLS 和 WireGuard 的节点出站结构。

### Windows 缓存处理

- 正式桌面连接显式传入 `cacheFile: false`；不改变共享配置生成器的默认值，避免影响移动端平台自行管理的缓存行为。
- 节点健康检查已经关闭缓存，保持不变。
- 移动端配置不依赖本次缓存修复；若平台自身管理规则集缓存，则沿用平台现有行为。

## 错误处理与界面

- 删除“三组远程 DNS/代理链路均不可用，请检查节点或网络”提示。
- sing-box 启动失败时直接显示真实的核心错误，例如缓存权限、配置错误或节点握手错误。
- 用户主动断开、切换节点、退出应用和系统重启时的代理清理逻辑保持不变。

## 测试要求

- 配置测试确认不存在 `remote-cloudflare`、`remote-google`、`remote-quad9`，DNS 最终解析器为 `local`。
- Provider 测试确认一次连接只启动一次平台连接，不执行 DNS 轮换或连接后 HTTP 204 强制验证。
- Windows 服务测试确认正式连接生成的配置不启用 `experimental.cache_file`。
- 现有节点 HTTP 204 检查、全节点检查、手动停止、系统代理恢复测试继续通过。
- 构建标记递增一位，便于截图确认运行的是本次修改后的程序。

## 不在本次范围

- 不重新设计新的远程 DNS 或自定义 DNS 界面。
- 不修改节点健康检查的 `http://www.gstatic.com/generate_204` 规则。
- 不修改订阅解析、节点协议字段、桌面 UI 布局或 GitHub 发布结构。
