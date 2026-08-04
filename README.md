# Forge VPN

Forge VPN 是一款基于 Flutter 和 sing-box 的多平台 VPN 客户端，支持 Windows、Android 和 iOS。它提供全局代理、智能分流、系统代理管理、节点可用性检测和订阅导入功能。

Forge VPN is a cross-platform VPN client for Windows, Android and iOS. It integrates sing-box and supports VLESS, VMess, AnyTLS, Trojan, Shadowsocks, Hysteria2 and WireGuard nodes.

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
