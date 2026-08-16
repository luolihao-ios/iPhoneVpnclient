# Forge VPN 最近迭代记录

项目首页与搜索关键词说明： [README](../README.md) · [SEO 关键词摘要](seo-keywords.md)

更新时间：2026-08-16

## 0.1.5+3 发布备注

- Windows 顶栏固定显示完整构建标记 `Windows · 0.1.5.003`，截图即可确认当前运行包是否包含本轮修改。
- Windows 全节点检测改为单个 sing-box 批量会话，通过 Clash API URLTest 分别测试每个 outbound，避免逐节点反复启动核心。
- URLTest 使用 `https://www.gstatic.com/generate_204`，保留全节点检查、并发检测和手动停止能力；节点结果直接采用核心返回的真实延迟。
- 订阅导入期间显示“正在导入…”，并阻止重复点击造成并发请求。
- 新增真实内置 sing-box 启动回归测试，确保批量检测配置不仅能生成，也能被 Windows 核心实际接受。

## 0.1.5+2 发布备注

- 修复部分订阅服务以 HTTP `200` 响应但返回空正文时被误判为导入成功、最终显示零节点的问题。
- 对空 `200` 响应自动使用 `flclash` 客户端标识重试；该类服务会据此返回实际 Clash YAML/订阅内容。
- 设置页构建标记升级为 `0.1.5.002`，用于确认已安装本次修复。

## 0.1.5+1 发布备注

- 三端统一使用 `0.1.5+1` 版本号；设置页显示构建标记 `0.1.5.001`。
- 新增 Clash YAML 与 sing-box JSON 的 Hysteria2 节点导入，兼容密码、SNI、ALPN、跳过证书校验、Salamander 混淆及上下行带宽。
- Hysteria2 节点会持久化保存，并在 Windows、Android、iOS 共享的 sing-box 配置中生成原生 `hysteria2` outbound。
- 无法识别的单个订阅节点会被跳过，不会中断同一份订阅中其他可解析节点的导入。

## 0.1.4+1 发布备注

- 三端统一使用 `0.1.4+1` 版本号；设置页显示构建标记 `0.1.4.001`，便于确认运行的是本次修复版本。
- 回退 Cloudflare、Google、Quad9 三组远程 DoH 自动切换和正式连接后的 HTTP 204 强制验证，三端恢复为一次平台连接。
- DNS 恢复为本地 `223.5.5.5`；智能分流的中国域名、中国 IP 直连规则保持不变。
- Windows 正式连接禁用默认 `cache.db`，修复 `initialize cache-file: open cache.db: Access is denied` 导致核心启动失败的问题。
- 节点列表 HTTP 204 可用性检查保持不变，不受本次正式连接流程回退影响。

本文记录最近一轮 Windows 端与移动端功能同步、节点检测、界面和发布流程的完成情况。

## Windows 端功能同步

- Windows 端沿用移动端的功能内容，同时使用适合桌面窗口的布局、导航栏和节点表格。
- 支持全局代理和智能分流两种路由模式。
- 支持系统代理自动设置、恢复和清理，关闭连接或退出程序时会清理代理状态。
- 支持托盘运行和退出确认，关闭窗口不再直接结束后台运行。
- 移除重复的品牌栏和多余图标，窗口标题统一为 `Forge VPN`。
- Windows 端自动发现 Release 目录、应用目录和常用目录中的 `sing-box.exe`。
- Windows 端启动时会恢复本地订阅和节点，并自动发起一次节点检查。

## 订阅与协议

- 支持 HTTPS 订阅地址、Stash 安装链接和复制粘贴导入。
- 订阅输入期间 provider 更新不会覆盖用户正在编辑的地址。
- 已导入订阅卡片默认折叠，点击标题可展开；键盘完成会导入订阅、收起键盘和卡片。
- 支持 VMess、VLESS、Trojan、Shadowsocks、Hysteria2、AnyTLS 和 WireGuard 节点。
- AnyTLS 节点保留 SNI、跳过证书校验、会话检查间隔和最小空闲会话数等配置。
- 订阅节点和选中节点会持久化，程序重启后可直接恢复使用。
- 订阅中的流量统计、重置时间和到期时间等元数据不会被当作节点显示。

## 节点检测与延迟

- Windows 节点可用性检查会启动临时 sing-box，通过代理请求境外出口 IP 服务验证节点是否真正可用。
- 可用性验证和界面延迟显示分离：延迟使用节点服务器的 TCP 握手时间，避免把境外 IP 查询耗时显示成延迟。
- 检查任务使用固定的本批节点快照，避免节点状态更新触发排序后跳过节点。
- 单个节点检查超过 10 秒会标记为不可用。
- 整批检查超过 30 秒会结束检查，并将剩余“检查中”节点标记为不可用。
- 启动检查出现异常时会记录日志并清理残留的“检查中”状态。
- 节点检查结果按可用性和延迟排序，显示可用数量、延迟和连接状态。

## 节点地区分组

- 支持地区代码前缀，例如 `HKG-`、`SGP-`、`JPN-`。
- 支持英文国家名，例如 `Japan`、`Singapore`、`United States`。
- 支持中文国家/地区名前缀，例如：
  - `日本-jpli` → 日本
  - `新加坡-sgli2` → 新加坡
  - `美国-us-vip-1` → 美国
  - `香港-hk-vip-1` → 香港
  - 同时识别 `韓國`、`臺灣`、`英國` 等繁体写法。
- 无法识别地区的节点归入“其他”。同一地区的节点会合并到同一个地区卡片中。

## Windows 图标与安装包

- Windows 应用图标已更换为“锻造火花 + F”几何标志，避免与 FlClash 的蓝色折线图标混淆。
- 图标资源：`windows/runner/resources/app_icon.ico`。
- 新增 Inno Setup 安装脚本：`installer/forge-vpn.iss`。
- 新增构建脚本：`scripts/build_windows_installer.ps1`。
- 安装包包含 Flutter Release 文件、`sing-box.exe` 和运行所需的 `data` 目录。
- 安装程序支持开始菜单快捷方式、可选桌面快捷方式和卸载。
- Release 输出目录为 `dist/`，已加入 `.gitignore`，避免安装包被误提交到源码仓库。

## GitHub 发布

- 当前仓库已迁移到：<https://github.com/luolihao-ios/iPhoneVpnclient>
- Windows Release 页面：<https://github.com/luolihao-ios/iPhoneVpnclient/releases/tag/v0.1.1-windows>
- 同一个 Windows Release 同时提供 `ForgeVPN-Setup-0.1.0.exe`、`ForgeVPN-Setup-0.1.1.exe` 和 `ForgeVPN-Setup-0.1.2.exe`，旧版本继续保留下载。
- 后续 Windows 发包统一上传到现有 Release `v0.1.1-windows`，不再为每个版本单独创建 Release；每次只新增对应版本的 `.exe` 安装包，保留历史安装包下载。
- GitHub 自动生成的 `Source code (zip)` 和 `Source code (tar.gz)` 保持平台默认状态，不额外上传源码压缩包。
- 发布步骤：递增 `pubspec.yaml` 的版本和构建号，运行 `scripts/build_windows_installer.ps1`，再执行 `gh release upload v0.1.1-windows dist/ForgeVPN-Setup-<版本>.exe`。
- GitHub 自动显示的 `Source code (zip)`、`Source code (tar.gz)` 链接由平台生成，无法从单个 Release 中隐藏；项目没有额外上传源码压缩包。
- 安装包 SHA-256：

  `ED873F3BFD8381AD01FF3A46F9AADA2C152035F2A77605323B8A03F706A41E46`

### iOS IPA 发布与安装说明

- GitHub Actions 的 iOS 构建会生成 `forge-vpn-ios-real-vpn.ipa`。
- 手动运行 GitHub Actions 时会同时创建 GitHub Release，并将 IPA 作为 Release 附件。
- 当前 IPA 使用 Ad Hoc 描述文件，仅支持已注册 UDID 的 iPhone/iPad 真机。
- Ad Hoc IPA 不能直接导入 TestFlight；TestFlight 版本必须通过 App Store Connect 单独上传。
- 越狱设备可使用相应侧载工具安装，实际可用性取决于设备和工具。

## 验证记录

已通过：

```text
flutter analyze lib/providers/app_provider.dart
flutter analyze lib/core/node_grouping.dart
flutter test test/singbox_service_test.dart
flutter test test/node_grouping_test.dart
flutter build windows --release
Inno Setup 7 编译 ForgeVPN-Setup-0.1.0.exe
```

## 后续维护建议

- 新增节点协议时，同时更新订阅解析、sing-box 配置生成、节点地区分组和安装包验证。
- 修改 Windows UI 时保持移动端的信息一致性，但不要直接复制移动端布局。
- 发布新版本时同步更新 `pubspec.yaml`、安装脚本中的 `MyAppVersion`、Release 标签和本文记录。
