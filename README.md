# Forge VPN

Forge VPN 是一款基于 Flutter 和 sing-box 的多平台 VPN 客户端，支持 Windows、Android 和 iOS。它提供全局代理、智能分流、系统代理管理、节点可用性检测和订阅导入功能。

Forge VPN is a cross-platform VPN client for Windows, Android and iOS. It integrates sing-box and supports VLESS, VMess, AnyTLS, Trojan, Shadowsocks, Hysteria2 and WireGuard nodes.

## 机场与订阅选择指南

Forge VPN 是客户端，不销售机场订阅或代理线路。你可以导入自己信任的订阅地址，再使用下面的标准比较不同服务和节点。此处的“机场”泛指提供代理订阅的服务商；本项目不对任何服务商排名、背书或保证可用性。

### 选择订阅时重点看什么

| 维度 | 建议关注点 |
| --- | --- |
| 线路稳定性 | 高峰期是否容易断线、丢包或抖动，是否有多个地区和备用线路 |
| 协议兼容性 | 是否提供 VLESS、VMess、AnyTLS、Trojan、Shadowsocks、Hysteria2 或 WireGuard 等适合自己网络环境的协议 |
| 解锁与出口 | 节点出口地区是否符合需求；流媒体、AI 服务和其他站点的可用性应以实际测试为准，不应只看宣传 |
| 价格与流量 | 月流量、倍率、设备数、限速规则、退款政策和长期成本是否透明 |
| 隐私与服务 | 订阅链接、账号和节点凭据的保护方式，服务商的日志政策、更新频率和售后响应 |
| 口碑与数据 | 优先参考可复现的测速、丢包和高峰期实测，不要只依据单次截图或短期促销 |

### 中文分档参考

| 分档 | 适合人群 | 主要取舍 |
| --- | --- | --- |
| 低价入门 | 轻度使用、偶尔访问境外服务 | 成本低，但高峰期稳定性和客服通常有限 |
| 性价比 | 日常办公、视频和多设备使用 | 价格、流量、地区覆盖较均衡，适合作为常用方案 |
| 高端专线 | 对延迟、稳定性和高峰期体验要求较高 | 成本更高，应确认线路质量、流量规则和服务承诺 |

### 用 Forge VPN 验证节点

1. 导入订阅后先检查节点列表，确认协议、地址、端口和分组信息正确。
2. 使用“检查”测试节点连接或握手延迟；超时节点会被标记为不可用，不代表所有网络和时间段都永久不可用。
3. 连接后再观察实际流量、出口 IP 和目标服务访问情况。TCP/握手延迟只能说明节点响应速度，不能单独证明网页、视频或 AI 服务一定可用。
4. 如果节点能连接但网页加载慢，分别排查 DNS、路由模式、系统代理、目标站点限制和线路高峰拥堵。

### 安全与合规提醒

- 请遵守所在地法律法规以及网络服务条款，仅使用有权使用的订阅和节点。
- 订阅 URL 往往包含密码、UUID 或其他凭据，不要公开发布、提交到截图或发送给陌生人；泄露后应立即更换订阅。
- 线路、价格、节点数量和服务能力可能随时变化。测速结果只代表测试时刻和当前网络环境，Forge VPN 不保证任何第三方线路持续可用。
- 本项目只提供客户端和开源实现，不代收费用、不托管用户订阅，也不对第三方服务的安全性负责。

### 节点与订阅测评模板

如果你要分享某个订阅的使用体验，建议按统一格式记录，方便其他人复核：

| 项目 | 记录内容 |
| --- | --- |
| 测试时间 | 日期、时区和是否为晚高峰 |
| 网络环境 | 家庭宽带、校园网、移动网络或其他网络类型 |
| 订阅信息 | 节点数量、协议分布、流量和有效期；不要公开完整订阅 URL |
| 节点结果 | 可用节点数、失败节点数、超时节点数和典型延迟范围 |
| 实际体验 | 网页访问、视频播放、下载和 AI 服务的实际结果 |
| 稳定性 | 连续使用时长、重连次数、速度波动和高峰期表现 |
| 成本与限制 | 价格、倍率、限速、设备数、退款和客服响应 |

单次测速不能代表长期质量。更可靠的结论应来自不同时间、不同网络和多个节点的重复测试。发布结果时请注明测试条件，避免把某一次成功或失败推广成绝对结论。

### 推荐使用流程

```text
选择可信订阅 → 导入并检查格式 → 批量检查节点 → 连接低延迟节点
      ↓                 ↓                  ↓             ↓
保护订阅凭据       确认协议参数       记录超时/失败       验证真实出口与业务
```

### 适合反馈的问题

- 订阅导入失败：提供脱敏后的协议类型、错误提示和导入时间。
- 节点检查失败：提供节点协议、地区、超时结果和日志中的错误片段。
- 连接成功但业务不可用：分别说明 DNS、路由模式、系统代理和目标服务表现。
- Windows 代理未恢复：说明是正常退出、托盘退出、强制结束还是重启后出现。

不要在 Issue、截图或日志中提交完整订阅地址、UUID、密码、私钥、服务器后台地址或个人网络信息。

### 维护与更新

Forge VPN 的版本迭代会记录在 [Windows Release](https://github.com/luolihao-ios/iPhoneVpnclient/releases/tag/v0.1.1-windows)、Android 和 iOS 发布页中，内容包括协议兼容、订阅导入、节点检查、系统代理恢复、界面和稳定性修复。欢迎提交可复现的问题、测试环境和日志，但请先移除订阅地址及其他敏感信息。

## 下载

- [Windows 安装包与历史版本](https://github.com/luolihao-ios/iPhoneVpnclient/releases/tag/v0.1.1-windows)
- [Android APK](https://github.com/luolihao-ios/iPhoneVpnclient/releases/tag/v0.1.0-android)
- [iOS 测试包与安装说明](https://github.com/luolihao-ios/iPhoneVpnclient/releases/tag/ios-test-103)

Windows Release 页面同时保留当前安装包和历史安装包。安装包内置 sing-box Windows x64 核心，不需要另外下载核心文件。

## 核心功能

- Windows VPN client、Android VPN 和 iOS VPN 多平台支持。
- 基于 sing-box 的 VPN/TUN 运行核心和图形界面（sing-box GUI）。
- 全局代理（Global Proxy）和智能分流（Smart Routing）。
- 系统代理自动设置、断开恢复和退出清理；Windows 关闭窗口后可托盘运行。
- 支持 HTTPS 订阅地址、复制粘贴导入和节点持久化。
- 节点可用性检查、境外出口验证、TCP/握手延迟检测和超时处理。
- 节点按中文、英文国家名和地区代码自动分组。
- Windows 端支持节点表格、日志诊断、流量统计和连接状态恢复。
- Android 端支持 libbox VPN/TUN、网络切换恢复和 VPN 诊断。
- iOS 端延续移动端订阅、节点和代理功能。

## 支持协议

- VLESS
- VMess
- AnyTLS
- Trojan
- Shadowsocks
- Hysteria2
- WireGuard

具体节点能力取决于订阅内容和 sing-box 核心版本。

## Windows 安装

1. 打开 [Forge VPN for Windows Release](https://github.com/luolihao-ios/iPhoneVpnclient/releases/tag/v0.1.1-windows)。
2. 在 Assets 中下载 `ForgeVPN-Setup-0.1.1.exe`；需要旧版时可下载 `ForgeVPN-Setup-0.1.0.exe`。
3. 运行安装程序，按向导完成安装。
4. 启动后导入订阅地址，选择节点并连接。

Windows 应用退出前会停止 sing-box 核心，并恢复连接前的系统代理设置。如果只是关闭窗口，应用会继续在系统托盘运行。

## Android 和 iOS 安装

- Android：从 [Forge VPN for Android Release](https://github.com/luolihao-ios/iPhoneVpnclient/releases/tag/v0.1.0-android) 下载 APK。首次运行 VPN/TUN 功能时需要授予系统 VPN 权限。
- iOS：从 [Forge VPN for iOS Release](https://github.com/luolihao-ios/iPhoneVpnclient/releases/tag/ios-test-103) 获取测试包。当前 iOS 包为 Ad Hoc 测试包，只支持已注册 UDID 的设备。

## 使用建议

1. 导入订阅后先点击“检查”确认节点可用性。
2. 选择延迟较低且检查结果为可用的节点。
3. 需要所有流量经过代理时选择全局代理；只代理特定流量时选择智能分流。
4. 退出软件前使用应用的退出流程，以便自动清理系统代理和后台核心。

## 开发环境

- Flutter stable 3.44 或更高版本
- Dart 3.12 或更高版本
- Windows 开发需要 Visual Studio C++ 桌面工具和 Windows SDK
- Android 开发需要 Android SDK 与 JDK
- iOS 开发需要 macOS、Xcode 和有效的签名配置

常用命令：

```bash
flutter pub get
flutter analyze
flutter test
flutter build windows
```

## 项目文档

- [最近迭代记录](docs/recent-iterations.md)
- [项目总结](PROJECT_SUMMARY.md)
- [README 与仓库 SEO 关键词说明](docs/seo-keywords.md)
- [Windows Release 发布记录](https://github.com/luolihao-ios/iPhoneVpnclient/releases/tag/v0.1.1-windows)

## 常见问题

### Windows 找不到 sing-box 核心怎么办？

优先使用 GitHub Release 中的 Windows 安装包。安装包已经包含 `sing-box.exe`。如果使用源码构建，请确认核心文件位于 Release 输出目录或应用能够发现的运行目录中。

### 为什么节点能连接但检查结果失败？

节点检查会单独启动临时核心并验证代理出口；网络波动、订阅节点临时限制或检查目标不可达，都可能导致检查失败。可以稍后重新检查或切换节点。

### 退出软件后系统代理会不会一直保留？

正常退出时，Forge VPN 会停止后台核心并恢复启动连接前的系统代理设置。若任务管理器强制结束进程，系统可能无法执行清理流程。

### AnyTLS 节点是否支持？

支持。AnyTLS 节点会按照订阅中的服务器、SNI、跳过证书校验和会话参数生成 sing-box 配置。

## 隐私与安全

Forge VPN 不提供订阅服务，也不内置任何服务器地址。请只使用你信任的订阅来源，并在公开反馈中隐藏订阅链接、服务器地址、UUID、密码和密钥。

## 许可证

本项目当前以仓库中的许可证和发布说明为准。第三方 sing-box 核心及其他依赖遵循各自的开源许可证。
