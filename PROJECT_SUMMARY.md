# Forge VPN 项目总结

更新时间：2026-07-18（第 4 轮 iOS 免费签名真 VPN 验证）

---

## 1. 项目说明

Forge VPN 是一个跨平台 VPN/代理客户端，使用 sing-box 作为核心代理引擎。

### 平台

| 平台 | 项目 | 技术栈 | 状态 |
|------|------|--------|------|
| Windows | `desktop-vpn-client` | Electron + Node.js + sing-box | ✅ 主流程可用 |
| iOS | `forge-vpn-flutter` | Flutter + Dart + sing-box | 🚧 测试中 |
| Android | `forge-vpn-flutter` | Flutter + Dart + Kotlin VpnService | 🚧 开发中 |

### 核心理念

- 导入订阅链接 → 解析节点 → 展示节点 → 检测可用性 → 一键连接
- 断开/退出时彻底清理代理，不留残留
- 双路由模式：Global proxy 全走代理 / Smart split 智能分流

---

## 2. 代码结构

### 2.1 桌面母版 `desktop-vpn-client`

```
desktop-vpn-client/
├── resources/bin/sing-box.exe         # sing-box 核心引擎
├── scripts/                           # PowerShell 脚本
│   ├── clear-system-proxy.ps1         # 清理 Windows 系统代理
│   ├── set-system-proxy.ps1           # 设置系统代理
│   ├── install-logon-proxy-cleanup.ps1 # 安装登录兜底清理
│   ├── install-singbox.ps1            # sing-box 安装
│   ├── start-singbox.ps1              # 启动 sing-box
│   ├── stop-singbox.ps1               # 停止 sing-box
│   └── ...
├── src/
│   ├── core/
│   │   ├── subscription.js            # 订阅解析 (Base64/JSON/URI)
│   │   ├── singbox.js                 # sing-box 配置生成 + 进程管理
│   │   ├── systemProxy.js             # WinHTTP/注册表代理管理
│   │   ├── nodeHealth.js              # 节点健康检测 (临时 sing-box)
│   │   ├── nodeLatency.js             # 节点排序统计
│   │   └── stats.js                   # 流量读取 (Clash API)
│   ├── main/
│   │   ├── main.js                    # Electron 主进程
│   │   └── preload.cjs                # IPC 桥接
│   └── renderer/
│       ├── index.html                 # 前端结构 (4 页)
│       ├── renderer.js                # 前端交互
│       └── styles.css                 # 样式
├── package.json
└── project_context.md                 # 详细上下文字档
```

### 2.2 Flutter 跨平台客户端 `forge-vpn-flutter`

```
forge-vpn-flutter/
├── lib/
│   ├── main.dart                      # Flutter 入口 + 主题 + 导航壳
│   ├── core/
│   │   ├── models/node.dart           # VpnNode 数据模型 (6 协议)
│   │   ├── subscription.dart          # 订阅解析 (Dart, 镜像 JS 逻辑)
│   │   ├── singbox_config.dart        # sing-box 配置生成
│   │   ├── node_health.dart           # 节点健康检测
│   │   ├── node_latency.dart          # 节点排序 + 可用计数
│   │   └── stats.dart                 # 流量统计
│   ├── providers/
│   │   └── app_provider.dart          # 全局状态管理
│   ├── screens/
│   │   ├── dashboard_screen.dart      # Dashboard: 状态卡 + 指标 + 节点表
│   │   ├── nodes_screen.dart          # Nodes: 订阅导入 + 节点列表
│   │   ├── settings_screen.dart       # Settings: 路由模式 + 系统代理
│   │   └── logs_screen.dart           # Logs: 日志列表
│   ├── services/
│   │   ├── singbox_service.dart       # sing-box 进程控制 (桌面)
│   │   ├── android_vpn_service.dart   # Android VpnService MethodChannel
│   │   └── ios_vpn_service.dart       # iOS NETunnelProvider MethodChannel
│   └── widgets/
│       └── responsive.dart            # 自适应布局 breakpoints
├── ios/
│   └── Runner/
│       ├── VpnPlugin.swift            # Flutter ↔ iOS 原生桥接
│       ├── PacketTunnelProvider.swift  # iOS TUN 隧道 + sing-box 集成
│       └── build-singbox-ios.sh       # gomobile 编译 sing-box 脚本
├── golib/ios/                         # Go gomobile 绑定
│   ├── main.go                        # sing-box iOS 绑定入口
│   ├── tools.go                       # golang.org/x/mobile 依赖
│   └── go.mod
├── scripts/
│   └── disable-codesign.py            # CI: 禁用代码签名脚本
└── .github/workflows/build-ios.yml    # GitHub Actions CI
```

---

## 3. 项目进度

### Windows (desktop-vpn-client) ✅ 主流程可用

**已完成：**
- 订阅导入 + 节点解析 (Base64/JSON/URI)
- sing-box 集成 (HTTP/SOCKS/Clash API)
- 节点真实可用性检测 (YouTube HTTPS)
- 节点表 + Ping + Available + Status 列
- Start/Stop 一键连接
- Global proxy / Smart split
- 系统代理自动设置 + 清理
- WinHTTP 代理管理
- 托盘后台运行 + 右键菜单
- 退出时清理代理
- 重启/注销同步清理代理
- 登录后兜底清理脚本

**待验证：**
- 开着 VPN 重启后的代理清理 —— 需要真实重启测试

### iOS (forge-vpn-flutter) 🚧 测试中

**已完成：**
- Dashboard / Nodes / Settings / Logs 四页面
- 订阅解析 (Dart)
- 节点健康检测
- 节点表格 (Node/Protocol/Endpoint/Ping/Available/Status)
- Check 按钮 + 可用数量
- 双击连接
- 状态徽章 (Connected/Selected/Ready)
- 自适应布局 (phone/tablet/desktop)
- iOS NETunnelProvider + sing-box 集成 (gomobile)
- CI 自动编译

**进行中：**
- iOS 真机运行时调试
- iOS 正式 VPN 权限签名方案（免费 Apple ID 已验证不能启动 Packet Tunnel）

### Android (forge-vpn-flutter) 🚧 开发中

- Android VpnService 基础桥接就绪
- 尚未实际测试

---

## 4. Bug 修复时间线（今晚 2026-07-17）

所有修改在 `forge-vpn-flutter` 仓库。

| # | 问题 | 修改 | Commit |
|---|------|------|--------|
| 1 | iOS Dashboard 只有横向 chips，缺少桌面版的完整节点表格 | 替换为 6 列节点表 + Check 按钮 + 可用数 + 状态列 + 双击连接 | `9 files changed` |
| 2 | Nodes 页面状态徽章只有 Selected/Tap，没有 Connected | 改为 Connected(绿)/Selected(蓝)/Ready(默认) | 同上 |
| 3 | Settings 缺少 System proxy 信息 | 新增 System proxy 分组 + 托管提示 | 同上 |
| 4 | PacketTunnelProvider.swift 纯透传，没有 sing-box 集成 | 重写为 sing-box gomobile 绑定 + TUN fd/packetFlow 双模式 + DNS 配置 + 局域网排除 | 同上 |
| 5 | Go 绑定代码 `package main` 不被 gomobile 支持 | 改为 `package singbox` | `2 files` |
| 6 | sing-box API 猜错：`box.ParseConfig`/`TUNOptions`/`ListenPrefix`/`box.Version` 都不存在 | 改为 `json.Unmarshal(option.Options)` + JSON 层 tun fd 注入 + `constant.Version` | `2 files` |
| 7 | CI sing-box 版本 `v1.10.6` 不存在 | 修正为 `v1.10.0` | 同上 |
| 8 | `nodes` 和 `availableCount` 未定义的 Dart 编译错误 | 改为 `provider.nodes` + `.where(healthStatus == available).length` | `efbb55e` |
| 9 | `FeedTunPacket`/`ReadTunPacket` 被 revert 从 Go 代码删除，Swift 仍引用 | 重新添加到 `golib/ios/main.go` | `0b6b393` |
| 10 | Swift 调用 gomobile API 签名不匹配（closure 传给 protocol、Start 不会 throw、Int32 应为 Int） | 改用 `SingboxLogCallbackProtocol` 类 + 返回值检查 + `Int` | `0b6b393` |
| 11 | `VpnError` 在两个 Swift 文件中重复定义 | 从 `VpnPlugin.swift` 中移除，保留 `PacketTunnelProvider.swift` 的版本 | `b76ade6` |

---

## 5. GitHub Actions 构建问题分阶段记录

### 阶段 1：初始 CI 没有 sing-box framework

**现象：** CI 只有 `flutter build ios`，没有编译 sing-box iOS framework 的步骤。

**处理：**
- 添加 `build-singbox-framework` job，用 `gomobile bind` 编译 `Singbox.xcframework`
- Go 绑定代码放在 `golib/ios/`
- CI 拉取 `sagernet/sing-box` 源码，注入绑定，编译 framework
- framework 作为 artifact 传给 `build-ios` job

### 阶段 2：`package main` 不被 gomobile 支持

**错误：** `gomobile: binding "main" package is not supported`

**处理：** Go 包名改为 `package singbox`。

### 阶段 3：sing-box API 对接失败（多次编译报错）

**问题 3a：** `golang.org/x/mobile` 不在模块依赖中
- **处理：** `go.mod` + `tools.go` + CI 中 `go get golang.org/x/mobile@latest`

**问题 3b：** `golang.org/x/mobile@v0.0.0-20241204231617-5e49bdcd6d1a` 不存在的 pseudo-version
- **处理：** 不指定版本，让 CI 的 `go get @latest` 自动解析

**问题 3c：** API 不匹配：
- `box.ParseConfig` → 不存在，改为 `json.Unmarshal` 到 `option.Options`
- `option.TUNOptions` → 不存在，正确字段是 `TunOptions`，改为 JSON 层注入
- `option.ListenPrefix` → 不存在，改为字符串
- `option.TUNStackSystem` → 不存在，改为 `"system"`
- `box.Version` → 不存在，改为 `constant.Version`

**处理：** 重写整个 `main.go`，使用 JSON map 操作注入 TUN fd。

### 阶段 4：CI 需要 Development Team 才能编译（签名问题）

**问题 4a：** `Building a deployable iOS app requires a selected Development Team`

尝试方案：
1. ❌ `--no-codesign` → Flutter 仍然在内部校验 Development Team
2. ❌ Python 脚本 patch pbxproj → Flutter 的 `Upgrading project.pbxproj` 步骤会覆盖修改
3. ❌ 直接 xcodebuild → 缺少 Flutter 生成的 framework 缓存
4. ✅ `flutter build ios --release --no-codesign || true` → Xcode 实际编译成功，但 Flutter 后置校验拒绝
5. **最终方案：** 编译失败后直接拿 `build/ios/Release-iphoneos/Runner.app` 打包 .ipa

**现状：** CI 生成 unsigned .app → 打包 .ipa → 上传 artifact。用户拿到后需手动签名或用 AltStore 侧载。

### 阶段 5：YAML 语法错误

**问题：** 内联 Python 脚本的引号破坏 YAML 解析

**处理：** 拆到独立文件 `scripts/disable-codesign.py`，CI 中一行调用

### 阶段 6：revert/rebase 导致代码撕裂（Go ↔ Swift API 错位）

**根因：** `d7379ea` 一次性改了 Go + Swift + Xcode，回滚时 Go 的 `FeedTunPacket`/`ReadTunPacket` 被删但 Swift 引用没同步。后续 rebase 进一步切碎了文件状态。

**现象（CI 反复挂，错误一直在变）：**
1. 16KB .app stub — Flutter 诊断说 Development Team 问题，实际是 Dart 编译错误
2. `DashboardScreen` 缺少 `nodes`/`availableCount` — 用了 undefined getter
3. `SingboxSetLogCallback` 传 closure — gomobile 需要 ObjC protocol 类
4. `SingboxStart` 加了 try — 实际不 throw，返回 String?
5. `tunFd: Int32` — gomobile 桥接是 `Int`
6. `SingboxFeedTunPacket`/`ReadTunPacket` 签名错 — gomobile 用 `Data?` 不是 unsafe pointers
7. `VpnError` 在两个 Swift 文件中重复定义

**处理：**
- 重新添加 `FeedTunPacket`/`ReadTunPacket` 到 `main.go`
- Swift 全部改用 gomobile 生成的正确桥接签名
- 移除 `VpnPlugin.swift` 中的重复 `VpnError`
- CI workflow 去掉 `|| true`，直接报错
- `DEVELOPMENT_TEAM` 和 `CODE_SIGN_ENTITLEMENTS` 直接烙入 `project.pbxproj` 而非 Python 脚本

---

## 6. 当前状态快照

```
GitHub: luolihao-aicode/iPhoneVpnclient
```

### ✅ 已解决（2026-07-17 第 2 轮）

- **16KB .app stub 构建失败：** root cause 是 Dart 编译错误 + Go/Swift API 错位，非 Development Team 问题
- **`DEVELOPMENT_TEAM` 配置固化：** 直接烙入 `project.pbxproj`（`CODE_SIGN_STYLE=Manual; DEVELOPMENT_TEAM=ABCD123456`），不再依赖 Python 脚本
- **`Runner.entitlements`：** 重新创建，含 VPN 网络扩展权限
- **`Singbox.xcframework` 链接：** 重新添加到 Frameworks + Embed Frameworks 阶段
- **Go/Swift API 对齐：** gomobile 桥接签名全部修正
- **CI 不再吞错误：** 去掉 `|| true` + 去掉 `continue-on-error`
- **Swift Package Manager：** 通过 `enable-swift-package-manager: false` 禁用，消除混合警告

### 第 3 轮修复摘要

详见 [第 8 节：第 3 轮 CI 调试记录](#8-第-3-轮-ci-调试记录2026-07-17-0615--0647)。

本轮通过 3 次 commit 修复了 6 个问题：

| # | 问题 | commit |
|---|------|--------|
| 1 | iOS 键盘盖导航 | `62e1556` |
| 2 | 缺少扩展 Target → VPN 不工作 | `62e1556` |
| 3 | pbxproj 格式错误（组引用错位）| `cc386b3` |
| 4 | VpnError 跨 Target 不可见 | `197bf8d` |
| 5 | VpnPlugin 跨 Target 引用（8 处）| `e2059de` |
| 6 | Build phase 顺序错误 | `e2059de` |

### 第 4 轮验证摘要

详见 [第 9 节：第 4 轮 iOS 免费 Apple ID 真 VPN 验证记录](#9-第-4-轮-ios-免费-apple-id-真-vpn-验证记录2026-07-17--2026-07-18)。

本轮目标不是绕开 VPN，而是验证：GitHub Actions 生成带 `ForgeVpnPacketTunnel.appex` 的真 VPN IPA 后，爱思助手使用免费 Apple ID 是否能签名、安装并启动 Packet Tunnel。

| # | 结论/问题 | 结果 | commit |
|---|-----------|------|--------|
| 1 | Actions artifact 下载慢 | 用 GitHub CLI 登录和 `gh run download` 作为替代下载方式 | 无代码提交 |
| 2 | 真 VPN IPA 打包结构 | 改为 `forge-vpn-ios-real-vpn.ipa`，使用 `ditto` 打包，并上传 `ios-build-inspection.txt` | `7e0a4a6` |
| 3 | `.appex` 没有扩展可执行文件 | 修正扩展 `Sources` build phase 位置；后续改为 CI 单独 `xcodebuild -target ForgeVpnPacketTunnel` 编译扩展后复制进 `Runner.app/PlugIns` | `20a9822`, `fa9d0f0` |
| 4 | `ForgeVpnPacketTunnel.swiftmodule` / Flutter bridging header 问题 | 移除 Runner 对扩展的显式依赖；扩展 target 不再使用 Runner 的 Flutter bridging header | `fa9d0f0`, `d25bed0` |
| 5 | 扩展安装 placeholder 缺少 bundleVersion | 扩展版本号改为 `MARKETING_VERSION=0.1.0`、`CURRENT_PROJECT_VERSION=1`，CI 增加版本号检查 | `c25dec1` |
| 6 | 免费 Apple ID 真机运行 VPN | IPA 可签名、可安装、App 可打开；`NETunnelProviderManager.loadAllFromPreferences()` 返回 `permission denied`，说明免费签名不具备 Packet Tunnel 权限 | 真机日志验证 |

## 8. 第 3 轮 CI 调试记录（2026-07-17 06:15 ~ 06:47）

### 测试 → Bug → 修复循环

```
昊哥 Windows 推送 → GitHub Actions 构建 → 昊哥下载 .ipa → 爱思助手安装 → 实测反馈
    ↑                                                                        ↓
    └────────── 我改代码/文档 → git commit → 昊哥再推 ────────────────────┘
```

### 本轮修复摘要

| # | 问题 | 现象 | 修复 | commit |
|---|------|------|------|--------|
| 1 | iOS 键盘盖导航 | Nodes 页面输入 URL 后键盘不消失，无法切页 | `GestureDetector` + `keyboardDismissBehavior` + FocusNode | `62e1556` |
| 2 | 缺少扩展 Target | VPN 连接失败，Settings > VPN 不显示 | 创建 ForgeVpnPacketTunnel target (+ Info.plist、pbxproj 脚本) | `62e1556` |
| 3 | pbxproj 格式错误 | CocoaPods 解析失败：Dictionary missing value | 扩展组引用插错位置（在 RunnerTests 组定义内部），移正 | `cc386b3` |
| 4 | VpnError 跨 Target 不可见 | CI 编译失败：Cannot find 'VpnError' in scope | PacketTunnelProvider 移到扩展后 Runner 看不到它定义的 VpnError，加回 VpnPlugin.swift | `197bf8d` |
| 5 | VpnPlugin 跨 Target 引用 | CI 编译链接失败（实际 8 处引用） | 扩展不能引用主 App 的 VpnPlugin，全部改为 os_log | `e2059de` |
| 6 | Build phase 顺序错误 | Embed App Extensions 排在 Sources 之前 | 移到 Resources 之后、Embed Frameworks 之前 | `e2059de` |

### 关键修复详解

#### 问题 3：pbxproj 组引用错位

one-pass 脚本中判断 `331C8082294A63A400263BE5 /* RunnerTests */` 时有二义性：
- `RunnerTests /* RunnerTests */,` → children 列表中的引用（应插入扩展组引用）
- `RunnerTests /* RunnerTests */ = {` → 组定义头（误插入导致 `=` 和 `,` 冲突）

**修复：** 匹配改为检查行尾是否为 `,`。

#### 问题 4：VpnError 跨 Target

- 修复前：`VpnError` 定义在 `PacketTunnelProvider.swift`，Runner Target 可访问（同 Target）
- 修复后：`PacketTunnelProvider.swift` 移到了扩展 Target → Runner 访问不到
- **修复：** 在 `VpnPlugin.swift` 中重新定义 `VpnError`，两 Target 各有一份

#### 问题 5：扩展不能引用主 App 类

iOS 扩展运行在独立进程，`PacketTunnelProvider.swift` 中 8 处 `VpnPlugin.sendLog/sendStatus` 调用在链接时会找不到符号。

全部替换为 `os_log(.info, ...)`：

| 原代码 | 替换为 |
|--------|--------|
| `VpnPlugin.sendLog("[sing-box] %s", msg)` | `os_log(.info, "[ForgeVPN] [sing-box] %{public}@", msg)` |
| `VpnPlugin.sendStatus("connected", ...)` | 删除（NEVPNManager 自动处理状态） |
| `VpnPlugin.sendStatus("disconnected", ...)` | 删除 |

#### 问题 6：Build phase 顺序

原始 -> 修复后：
```
buildPhases = (
  [Embed App Extensions],   ❌ 放最前面，扩展还没编译
  Run Script,
  Sources,
  Frameworks,
  Resources,
  Embed Frameworks,
  Thin Binary,
)

→

buildPhases = (
  Run Script,
  Sources,
  Frameworks,
  Resources,
  [Embed App Extensions],  ✅ 放 Resources 之后，扩展已编译
  Embed Frameworks,
  Thin Binary,
)
```

### 当前项目结构

```
forge-vpn-flutter/
├── ios/
│   ├── Runner/                          # 主 App Target
│   │   ├── VpnPlugin.swift              # Flutter ↔ iOS 桥接（MethodChannel）
│   │   ├── AppDelegate.swift
│   │   ├── PacketTunnelProvider.swift
│   │   ├── Info.plist                   # NEProviderClasses 声明
│   │   └── Runner.entitlements
│   ├── ForgeVpnPacketTunnel/            # 扩展 Target（新建）
│   │   └── Info.plist                   # NSExtension 声明
│   └── Runner.xcodeproj/
│       └── project.pbxproj             # 2 targets: Runner + ForgeVpnPacketTunnel
└── scripts/
    ├── patch-pbxproj.py                # Xcode 项目修改脚本
    └── fix-pbxproj.py                  # 格式修复脚本
```

### 当前测试要点（第 3 轮，待测）

1. ❓ **VPN 配置显示** — Settings > VPN 是否有 "Forge VPN"
2. ❓ **VPN 连接** — Dashboard 选节点 → 连接是否成功
3. ❓ **订阅导入** — 输入 URL → Import → 节点列表是否正常
4. ❓ **节点检测** — Check 按钮能否检测节点可用性
5. ❓ **路由切换** — Settings 切换 Global proxy / Smart split
6. ❓ **断开连接** — 再次点击连接按钮断开

### 构建成功后安装步骤

1. GitHub Actions 下载 `forge-vpn-ios-real-vpn.ipa` artifact
2. 爱思助手 → 工具箱 → 签名（用个人 Apple ID 手动签名）
3. 爱思助手 → 我的设备 → 应用游戏 → 导入安装

> ⚠️ CI 产的 .ipa 是 unsigned，侧载一定要手动签名一步，不然装不上。

---

## 9. 第 4 轮 iOS 免费 Apple ID 真 VPN 验证记录（2026-07-17 ~ 2026-07-18）

### 本轮目标

验证“免费 Apple ID + 爱思助手”是否能安装并运行带 `NetworkExtension` / `Packet Tunnel Provider` 的真 VPN IPA。

本轮不再优先做去掉 VPN 扩展的诊断版，而是保留：
- `ForgeVpnPacketTunnel.appex`
- `com.apple.developer.networking.networkextension = packet-tunnel-provider`
- `NETunnelProviderManager` / `NEPacketTunnelProvider`
- sing-box gomobile framework

### 时间线

| 阶段 | 现象 | 根因 | 处理/结论 | commit |
|------|------|------|-----------|--------|
| 1 | 爱思签名报 43 | 初步怀疑是免费 Apple ID 不支持 Network Extension entitlement；但缺少设备日志，不能定案 | 改为构建真 VPN 验证包，不绕开 VPN | 计划阶段 |
| 2 | Actions artifact 下载慢 | GitHub Actions artifact 走海外链路，VPN 能访问不代表大文件下载快 | 建议使用 GitHub CLI：`gh run list` + `gh run download`；Release/OSS 可作为后续优化 | 无代码提交 |
| 3 | 需要稳定产出真 VPN IPA | 原 workflow 使用普通 zip，验证日志分散 | 产物改名为 `forge-vpn-ios-real-vpn.ipa`；使用 `ditto -c -k --sequesterRsrc --keepParent Payload`；上传 `ios-build-inspection.txt` | `7e0a4a6` |
| 4 | CI 检查发现 `.appex` 存在但缺少 `ForgeVpnPacketTunnel` 可执行文件 | 扩展 target 的 `Sources` build phase 在 `project.pbxproj` 中结构错位，导致扩展包像空壳 | 修正 `Sources` build phase 位置 | `20a9822` |
| 5 | `ForgeVpnPacketTunnel.swiftmodule` 找不到 | Runner 主构建链被显式绑定到扩展 target，触发跨 target module 查找；历史文档已有“不要加显式循环依赖”的记录 | 撤回 Runner → 扩展的显式 scheme/target 依赖；改为 CI 单独构建扩展后嵌入 | `fa9d0f0` |
| 6 | 单独构建扩展时报 `Flutter/Flutter.h` not found | 扩展 target 继承了 Runner 的 `SWIFT_OBJC_BRIDGING_HEADER`，该 header 引入 Flutter 的 `GeneratedPluginRegistrant.h` | 删除扩展三套配置中的 bridging header；Runner 保留 | `d25bed0` |
| 7 | `xcodebuild -target ... -derivedDataPath` 报参数错误 | 当前 Xcode 要求指定 `-scheme` / test 参数才能配合 `-derivedDataPath` | 改用 `CONFIGURATION_BUILD_DIR` 固定扩展输出目录 | `47ab5ab` |
| 8 | 爱思签名成功但安装失败 | 设备日志显示：`bundleVersion must be set in placeholder attributes for an app extension placeholder` | 扩展 `Info.plist` 不再使用 `$(FLUTTER_BUILD_NUMBER)`，改用扩展自己的 `$(CURRENT_PROJECT_VERSION)`；CI 增加版本号非空检查 | `c25dec1` |
| 9 | 新包安装成功，App 可打开，但连接 VPN 失败 | App 日志：`NETunnelProviderManager.loadAllFromPreferences()` 返回 `permission denied` | 结论：免费 Apple ID 可签名/安装真 VPN 包，但没有 Packet Tunnel 权限，无法读取/创建系统 VPN 配置 | 真机验证 |

### 当前验证结果

已验证：
- ✅ GitHub Actions 能构建带 `ForgeVpnPacketTunnel.appex` 的真 VPN IPA
- ✅ 爱思助手免费 Apple ID 可完成签名
- ✅ 修复扩展版本号后，IPA 可安装到 iPhone
- ✅ App 可打开，订阅/节点/UI 进入运行态
- ❌ 点击连接 VPN 失败：`VPN_ERROR: permission denied`
- ❌ `diagnose` 显示：`loadError: permission denied`

真机 App 日志：
```
Starting VPN (iOS TUN)...
Config: 1742 bytes
Node: USA-us-vip-ba (VMess)
[error] connect failed: code=VPN_ERROR, message=permission denied
VPN Error: permission denied
[diag] Running VPN diagnostics...
[diag] bundleId: com.example.forgeVpnFlutter.FW3AUPXP7M
[diag] appName: Forge VPN
[diag] loadError: permission denied
```

关键解释：
- 爱思签名会把主 App bundle id 改成类似 `com.example.forgeVpnFlutter.FW3AUPXP7M`
- 当前代码自动将 provider id 拼为 `com.example.forgeVpnFlutter.FW3AUPXP7M.tunnel`
- 安装日志也显示扩展 id 是 `com.example.forgeVpnFlutter.FW3AUPXP7M.tunnel`
- 因此本轮失败不是 provider bundle id 拼错，而是系统拒绝 `NETunnelProviderManager` 权限

### 结论

免费 Apple ID 的本轮结论：
- 可以签名
- 可以安装
- 可以打开 App
- 不能使用 Packet Tunnel VPN 能力

这说明真 VPN 实测需要付费 Apple Developer 账号和匹配的 provisioning profile。后续正式签名需要至少两份 profile：
- 主 App：`com.xxx.forgeVpnFlutter`
- Packet Tunnel 扩展：`com.xxx.forgeVpnFlutter.tunnel`

两者都必须包含对应的 VPN / Network Extension 能力，否则 `NETunnelProviderManager.loadAllFromPreferences()` 仍会返回 `permission denied`。

### 后续建议

1. **短期：** 保留免费签名包作为 UI/订阅/节点/日志验证包，但不要再用它验证真 VPN 权限。
2. **真 VPN 测试：** 已确认使用付费 Apple Developer 团队，并将最低系统版本调整为 iOS 15；为主 App 和扩展配置 App ID、entitlements 与匹配的 provisioning profile。
3. **CI：** GitHub Actions 导入证书、私钥、证书密码和两份 profile，直接构建已签名 IPA；打包前检查主 App 与扩展的有效 Network Extension entitlement。
4. **真机验收：** 下载 Actions 的签名 IPA 后，使用爱思助手安装；验证 Manager 创建、连接、流量路由、断开、前后台恢复和诊断输出。
5. **下载体验：** 如果 Actions artifact 下载慢，可使用 GitHub CLI；若测试频繁，再考虑上传 Release 或 OSS/COS。

### 遗留问题

1. **iOS 真 VPN 签名：** 免费 Apple ID 已验证无法启动 Packet Tunnel；需要付费 Apple Developer + 匹配 profiles
2. **智能分流规则：** 已移除 `.cn` 与手工域名白名单，改用 SagerNet 官方 `geosite-cn`（中国域名）和 `geoip-cn`（中国 IP）远程二进制规则集；规则经代理下载并由 sing-box 缓存。仍需真机验证首次下载、缓存命中和抖音流量直连。
3. **Android 实测：** Android VpnService 桥接就绪但尚未经过实际测试
4. **付费签名后的扩展实测：** 需要验证 Settings > VPN 配置显示、连接状态、扩展启动日志
5. **Singbox.framework 运行实测：** 付费签名通过后，如果 VPN 仍不通，需确认扩展运行时是否正确加载 `Singbox.xcframework`

---

## 10. Android 接口与状态管理（第 1 阶段）

### 范围

本阶段只补齐 Flutter 与 Kotlin 的 VPN 接口、授权和状态管理，不改动真实 sing-box/TUN 流量链路，也不以真机隧道可用为验收条件。

### 已确认的契约

- 通道保持为 `dev.forge.vpn/vpn_service`。
- Flutter → Kotlin：`requestPermission`、`connect(config)`、`disconnect`、`isRunning`、`getState`。
- Kotlin → Flutter：`onStatus(status, message)`、`onLog(line)`。
- 保留 `connected`、`disconnected`、`error`、`permission_granted`、`permission_denied`；新增 `ready`、`connecting`、`disconnecting` 只用于诊断和日志。
- `VpnBridge` 是 Android 连接状态、最近消息和授权状态的单一事实来源；`MainActivity` 仅负责显示系统授权界面并回传结果。
- Flutter 的权限等待不能替换全局 MethodChannel 回调；应用恢复时由 `getState` 重建状态。

### 实施计划

1. 先为 Dart 的状态回调和权限等待行为写失败测试。
2. 让 `AndroidVpnService` 安装一次通道回调，维护待完成的权限请求，并补齐 `getState` 与错误处理。
3. 在 Kotlin 中实现统一状态存储、权限命令、状态查询与 `MainActivity` 授权结果回传。
4. 将 `ForgeVpnService` 生命周期接入桥接状态，但不改变当前真实隧道实现。
5. 更新 Provider 对中间状态的日志处理，运行 Dart 测试、`flutter analyze` 与 Android debug 构建。

### 实施结果（2026-07-18）

- Flutter `AndroidVpnService` 已改为只注册一次 MethodChannel 回调；授权请求使用单独的 pending completer，不再覆盖日志和状态监听。
- 新增 `getState` 恢复流程；应用初始化时恢复 Android 授权与连接状态。
- Kotlin `VpnBridge` 已实现授权请求、状态查询、运行状态查询和统一状态存储；`MainActivity` 负责回传系统授权结果。
- `ForgeVpnService` 的连接、错误、进程退出和断开生命周期已改为写入统一桥接状态。
- 新增 Dart 通道测试与 Kotlin `VpnStateStore` 单元测试。
- Dart 测试、变更范围内的静态分析和 Kotlin 状态单元测试已通过。
- 2026-07-21 已将 Android 构建链调整为 Gradle 8.9 / AGP 8.7.3，并修复 `ForgeVpnService`、`VpnBridge` 的 Kotlin 编译错误及 Manifest 类名与 namespace 不一致问题。
- `:app:compileDebugKotlin` 与 `:app:assembleDebug` 已在 JDK 21 下通过；调试 APK 已生成于 `build/app/outputs/flutter-apk/app-debug.apk`。Gradle、AGP、Kotlin 的后续最低版本提示目前仍是警告，不影响本次 debug 构建。
- 2026-07-21 雷电模拟器实测为 `x86_64`；已补入官方 `sing-box-android-amd64`，并修复日志页在 Android 错误调用 iOS `diagnose` 导致的 `MissingPluginException`。Android `diagnose` 现在会返回 ABI、资产存在性、已提取二进制和 VPN 状态。
- 新 APK 已通过 `adb install -r` 安装并启动，启动日志未出现 `FATAL EXCEPTION`；Android Kotlin 单元测试 `:app:testDebugUnitTest` 通过。连接流程仍需在模拟器中导入节点后继续验证真实 TUN/节点流量。
- 2026-07-21 进一步定位到二进制路径问题：Flutter 资源实际位于 `flutter_assets/assets/binaries/`，原生代码误读为 `binaries/`。已统一修正资产读取与诊断路径，并新增资产路径回归测试；修复后的 `:app:testDebugUnitTest` 与 `:app:assembleDebug` 均通过。
- 2026-07-21 雷电实测诊断确认 `assetAvailable: true`、`installedBinary: true`；随后暴露 Android 目标 SDK 36 启动前台 VPN 服务缺少类型的问题。已在 `ForgeVpnService` 清单声明 `foregroundServiceType="specialUse"` 及 VPN 子类型属性，需重新构建安装后验证。
- 2026-07-21 真实连接实测：前台服务和 sing-box 二进制均已启动，但命令行返回 `unknown flag: --tun-fd`。这不是 ABI 或资源问题；当前 Android 实现仍缺少把 `VpnService` TUN fd 注入 sing-box 的平台层。官方 Android 客户端通过 libbox 的平台接口创建/提供 TUN，后续真实流量阶段需改为 libbox/AAR 集成或等效的原生 TUN 转接方案；暂不通过删除参数掩盖问题。

## 11. Android libbox 集成（第 2 阶段）

### 目标

将 Android 真 VPN 的核心启动方式从当前 CLI 进程方案切换为官方 sing-box `libbox` 平台接口：由 Kotlin `PlatformInterface.openTun()` 创建 Android TUN，并由 libbox 负责核心生命周期。删除当前已被实测证明不支持的 `--tun-fd` 参数。

### 已确认的设计

- **方案**：采用官方 `libbox.aar` 本地依赖，不移植完整 SFA 应用层，也不维护自定义 JNI FD 转接层。
- **版本**：固定 sing-box/libbox v1.13.14，与现有 `sing-box-android-arm64`、`sing-box-android-amd64` 资源版本保持一致。
- **构件位置**：AAR 放入 `android/app/libs/libbox.aar`；若 AAR 未包含 JNI，则按 ABI 放入 `android/app/src/main/jniLibs/`。构件由开发者在本机下载或构建，运行时不联网下载。
- **平台适配**：新增 Kotlin 适配层实现 libbox 的 `PlatformInterface`：
  - `openTun(options)` 使用 `VpnService.Builder` 映射 MTU、地址、路由、DNS、应用排除规则并返回 TUN fd；
  - `autoDetectInterfaceControl(fd)` 调用 `VpnService.protect(fd)`，避免核心连接回流到 VPN；
  - 保存并关闭 `ParcelFileDescriptor`，确保停止服务时无资源泄漏。
- **核心控制**：新增 libbox 控制器封装核心启动、停止、日志和错误回调。`ForgeVpnService` 只保留前台服务生命周期、通知和桥接状态转发，不再提取二进制、`Runtime.exec` 或监控 CLI 进程。
- **状态契约**：Flutter MethodChannel 契约保持不变；只有 libbox 启动成功后发送 `connected`，失败发送 `error`，停止时先停止核心再释放 TUN。
- **配置契约**：继续使用 Flutter 生成的 JSON；TUN fd 由平台接口提供，不再向 sing-box CLI 传递 `--tun-fd`。
- **文档约束**：本阶段设计、执行计划、构件版本、构建命令和雷电实测结果均追加到本文件，不新增设计文档。

### 实施计划

- [x] **任务 1：准备 libbox 构件**
  - 由开发者在本机获取/构建 v1.13.14 的 `libbox.aar` 及所需 ABI 原生库；
  - 放入约定目录后确认 AAR 可被 Gradle 解析，记录构件来源和 SHA-256。
- [x] **任务 2：接入 Gradle 依赖**
  - 修改 `android/app/build.gradle`，增加本地 AAR 依赖和 JNI 目录配置；
  - 执行 `:app:dependencies`，确认 `libbox` 只解析一次且无 ABI 冲突。
- [x] **任务 3：实现 Kotlin 平台适配层**
  - 新增 `LibboxPlatformInterface.kt`，实现 `openTun`、`autoDetectInterfaceControl` 和必要的平台回调；
  - 为 TUN 参数映射和 fd 释放增加可测试的辅助函数。
- [x] **任务 4：替换 ForgeVpnService 核心启动**
  - 新增 `LibboxServiceController.kt`，封装 libbox 命令服务/启动停止 API；
  - 删除 CLI 提取、`Runtime.exec`、`--tun-fd` 和进程监控代码；
  - 保留前台通知、状态上报、重复连接和断开清理。
- [ ] **任务 5：补齐测试和状态回归**
  - 增加 Kotlin 平台参数、状态转换和重复生命周期测试；
  - 运行 `:app:testDebugUnitTest`、Dart 静态分析和现有服务测试；
  - 运行 `:app:assembleDebug`，确认 APK 包含 AAR/JNI。
- [ ] **任务 6：雷电模拟器实测**
  - 安装新 APK，点击授权并连接节点；
  - 日志中确认不再出现 `unknown flag: --tun-fd`，状态进入 `connected`；
  - 验证断开、重连、应用重启恢复和诊断输出。

### 执行记录

2026-07-21 已由开发者构建并复制 v1.13.14 `libbox.aar` 到 `android/app/libs/libbox.aar`。AAR 内含 `armeabi-v7a`、`arm64-v8a`、`x86`、`x86_64` 四种 `libbox.so`；SHA-256 为 `F1B3A2D122CB4711241F21063E57972F53D30BC8EF77684358BFD6FEC3AD87EB`。
2026-07-21 已接入 Gradle 本地依赖、新增 `LibboxPlatformInterface`/`LibboxServiceController`，并将 `ForgeVpnService` 从 CLI/`--tun-fd` 切换为 libbox `CommandServer`。待 Android 编译和雷电实测完成后更新任务 5、6。
2026-07-21 用户本机已完成 `flutter build apk --debug`；最终生成 `build/app/outputs/flutter-apk/app-debug.apk`（约 389 MB）。中间出现的 Kotlin 增量缓存跨盘符关闭异常未阻止 APK 生成，后续可用 `flutter clean` 清理缓存后再构建。
2026-07-21 雷电模拟器首次点击连接时，libbox 已成功加载（诊断显示 `libboxVersion: 1.13.14`），但因未配置 `SetupOptions` 工作目录，命令服务尝试在只读位置创建 `command.sock`，日志为 `listen unix command.sock: bind: read-only file system`。已在 `LibboxServiceController` 启动前调用 `Libbox.setup`，将 `basePath`、`workingPath`、`tempPath` 分别指向应用 `filesDir`、外部 files 目录（不可用时回退到 `filesDir`）和 `cacheDir`，并开启 `fixAndroidStack`。需重新构建安装后复测连接。
2026-07-21 复测仍出现同一 Unix socket 错误；为绕过部分 Android 镜像对 Unix socket 的限制，已将 `SetupOptions.commandServerListenPort` 固定为本机回环端口 `35123`。该命令服务仅供进程内控制器使用，不改变 VPN 数据转发端口；需重新构建安装后继续验证。
2026-07-21 新 APK 已通过命令服务初始化并进入配置解析；雷电日志提示 `inbounds[1]` 使用已在 sing-box 1.13.0 移除的 `sniff`/`sniff_override_destination` legacy 字段。已从 SOCKS/TUN 入站删除这些字段，并在 `route.rules` 首条加入 `{ "action": "sniff" }`，保持原有协议嗅探行为。需重新构建安装后继续验证。
2026-07-21 连接状态已进入 `Connected`，说明节点配置已被 libbox 接受；后续数据日志出现 `no available network interface`，暂不能归因于机场节点。已按官方 Android 平台适配方式增强 `getInterfaces()`，从 `ConnectivityManager` 的网络、链路属性、DNS、传输类型、MTU、地址和接口 flags 构造 libbox 网络接口列表；同时修复移动端节点 Check 原先误调用空 CLI 路径的问题，Android/iOS 现在使用节点 TCP 可达性检查。
2026-07-21 雷电实际测试确认节点测速可用且 VPN 显示 `Connected`，但浏览器流量仍因默认接口未通知 libbox 而失败。已实现 `startDefaultInterfaceMonitor`，从 `ConnectivityManager.activeNetwork` 获取模拟器物理接口名/index（例如 `eth0`），在 TUN 建立前通知 libbox，避免把 VPN TUN 当作外层出口。
2026-07-21 新增默认接口后出现 native `libbox.so` `SIGABRT`；崩溃点仅显示 native 帧，结合 libbox `netip.MustParsePrefix` 解析路径定位为 Android IPv6 地址中的 `%接口名` 作用域标记。已按官方适配层方式去除 IPv6 zone 标记后再传给 libbox，避免非法前缀触发 abort。

### 12. 节点持久化与移动端自适应

2026-07-21 实测确认 VPN 已能连通并通过浏览器验证。针对重启后订阅节点丢失，Flutter 现在使用 `SharedPreferences` 保存订阅 URL、节点 JSON 列表和选中节点 ID；启动时恢复本地节点，不依赖重新联网。节点序列化补齐了 VMess 的 security/alterId、插件和 WireGuard reserved 等字段。

UI 保持自适应布局：手机/平板/桌面仍按屏幕尺寸切换导航和节点列表，但设备类型改用 `MediaQuery.shortestSide` 判断，因此横屏手机不会因为宽度变大而误切到桌面布局；真正的大尺寸雷电配置仍会使用平板/桌面布局。
2026-07-21 手机首页出现红色竖排 `RenderFlex overflowed` 提示，根因是订阅服务器卡片标题、`Check` 按钮和可用数量在窄屏共用一行导致横向溢出。已让手机端标题和操作区分两行显示，平板/桌面继续单行显示；新增响应式 Dashboard widget 回归测试。
2026-07-21 复测发现手机节点卡片仍有第二处横向溢出：节点 endpoint 文本与延迟文本在同一 Row 中均按固有宽度布局。已将 endpoint 包入 `Expanded` 并启用单行省略，保留延迟与状态徽章的固定可见空间。

### 13. AnyTLS 与复制后粘贴订阅

2026-07-21 新增 `NodeType.anytls`，支持 AnyTLS URI 和 JSON 节点，生成 sing-box 1.13.14 的 `type: anytls` outbound，并保留 TLS SNI、insecure、空闲会话检查间隔、超时和最小空闲会话数等字段。

订阅输入新增 `resolveSubscriptionInput`：普通 HTTPS 地址直接请求；`stash://install-config?url=<编码后的 HTTPS 地址>&name=...` 会提取并解码 `url` 后请求真实订阅。当前只支持复制后粘贴，不增加浏览器唤起应用的 Deep Link/Intent。

### 14. 临时 HTTPS 订阅的 403 兼容

2026-07-21 进一步确认：同一链接可在 FlClash 导入，但 Chrome 和 Forge VPN 返回 403。订阅服务因此按客户端标识返回内容；Forge VPN 已增加 `flclash` User-Agent 重试，并加入 Clash YAML `proxies` 列表解析，包含 AnyTLS 的 `sni` 与 `skip-cert-verify` 字段映射。

2026-07-21 对同一临时 HTTPS 地址进行对照测试：Forge VPN 和电脑 Chrome 均收到“禁止访问/HTTP 403”。由此确认拒绝发生在机场订阅服务器侧，尚未进入 Forge VPN 的 AnyTLS 节点解析流程；更换客户端请求头无法解决该链接本身的访问限制。

复制订阅得到的临时 HTTPS 地址在请求阶段返回 HTTP 403 时，尚未进入 AnyTLS/VMess 等节点解析流程，因此不能通过修改节点解析器解决。`fetchSubscription` 现在先使用应用标识请求；遇到 403 会先用 `flclash` User-Agent 重试，再用标准 Android 浏览器 User-Agent 兜底。请求仍返回 403 时，界面会提示链接已过期或服务器拒绝客户端，避免误认为是 AnyTLS 解析失败。

### 15. 系统语言本地化设计

#### 目标

支持简体中文和英文。应用启动时跟随手机系统语言；系统语言不是中文或英文时回退英文。节点名称、机场返回的备注、服务器地址、协议原名和原始日志保持不翻译。

#### 架构

- 使用 Flutter 官方 `flutter_localizations` 与 ARB 翻译资源：`app_zh.arb`、`app_en.arb`。
- `MaterialApp` 配置本地化代理和支持语言，不手动固定 `locale`。
- 页面通过 `AppLocalizations.of(context)` 获取翻译文字。
- `NodeType.label` 等模型层文本由页面侧按类型读取翻译，不把 `BuildContext` 放入数据模型。

#### 覆盖范围

- 导航、首页、节点页、设置页、日志页；
- 连接状态、测速指标、导入按钮、检查按钮、节点状态和空列表提示；
- 固定错误提示翻译前缀，动态错误原因和机场原始文本保持原样；
- AnyTLS、VMess、VLESS 等协议名称保持协议原名。

#### 实施与验证

1. 增加本地化配置和中英文 ARB 资源。
2. 逐页替换硬编码界面文字，不改 VPN、节点解析和连接状态逻辑。
3. 增加中文、英文和未知语言回退测试。
4. 检查中文长文本在手机窄屏上的布局，避免新的溢出。
5. 构建 APK 后在雷电模拟器切换系统语言并重启验证。

#### 当前实施记录（2026-07-21）

- [x] 已加入 `flutter_localizations`、`l10n.yaml`、中英文 ARB 资源和 `AppLocalizations`。
- [x] 已接入 MaterialApp 的系统语言解析，中文使用中文资源，其他语言回退英文。
- [x] 已替换主导航、首页、节点、设置和日志页面的固定界面文字。
- [x] 已加入协议类型本地化映射和中英文/回退单元测试。
- [ ] Flutter 测试、分析和 APK 构建待开发者在本机执行；Direct Dart 格式检查与 `git diff --check` 已通过。

### 17. 首页节点按地区分组

#### 目标

将订阅解析出的节点按节点名称前缀归类：首页使用地区父卡片包裹节点子卡片；Android 与 iOS 共用 Flutter 实现，后续不需要分别维护两套分组逻辑。

#### 规则

- 取节点名称第一个 `-` 之前的连续字母/数字作为地区代码，例如 `HKG-hk-vip-2` → `HKG`。
- 名称不符合地区前缀格式的节点归入 `OTHER`（其他）。
- 地区组和组内节点均保持订阅原始出现顺序。
- 地区代码的中文/英文显示由页面侧本地化；节点名称、服务器地址和协议名称保持原文。
- 父卡片显示地区名称和节点数量，子卡片保留原有选择、延迟、可用性、连接和双击连接行为。

#### 实施计划与记录

1. 为 `groupNodesByRegion` 编写顺序保持、未知地区回退的单元测试。
2. 新增纯 Dart 分组模型和地区代码提取函数。
3. 修改 Dashboard 手机卡片与平板/桌面表格，使两种布局都渲染地区父卡片和节点子项。
4. 增加地区名称中英文资源和本地化映射测试；不修改节点模型及 VPN 连接逻辑。
5. 由开发者在本机执行 Flutter 测试、分析和 APK 构建；iOS 真机/签名验证延后。

#### Windows 适配边界

项目保留 Flutter Windows 工程目录，因此上述共享 Flutter 功能会随 Windows 桌面构建生效；当前 Windows 端没有 VPN/TUN 原生服务、系统代理接管或 sing-box libbox 后端。Windows 真 VPN 需要另立原生网络层任务，本轮不把“界面可运行”误认为“系统流量已代理”。

#### 本轮实现记录

- [x] 新增 `lib/core/node_grouping.dart`，按节点名称前缀分组并保持原始顺序。
- [x] 新增地区名称本地化映射，支持常见地区代码和 `OTHER` 回退。
- [x] Dashboard 手机布局与平板/桌面表格均改为地区父卡片 + 节点子项。
- [x] 保留节点选择、连接、双击连接、延迟和健康状态行为。
- [x] 新增 `test/node_grouping_test.dart` 与地区本地化回归测试；Flutter 测试/分析由开发者本机执行。
- [x] 地区识别扩展为规范化键：支持地区代码前缀、国旗/国家名称，且会将分散出现的同一国家节点合并到同一父卡片。
- [x] 过滤 AnyTLS/Clash 订阅中的流量重置、流量统计和到期日期元数据条目，避免它们伪装成节点显示。
- [x] 针对雷电模拟器日志中的 `114.114.114.114:53` UDP DNS 请求增加直连路由，避免 AnyTLS 节点不返回 UDP DNS 导致浏览器无法解析域名。
- [x] 根据实测日志将 DNS 默认解析器从 AnyTLS 代理上的远程 DoT 改为可响应的本地 DNS，避免 `:853 i/o timeout` 阻断域名解析。
- [x] 移动端节点 TCP 检查优先使用 IPv4，避免雷电模拟器无可用 IPv6 路由造成“节点不可用”的误判。
- [x] 移除主导航的“节点”入口，抽取共享订阅导入卡并放置到 Dashboard 顶部；导入后仍由 Dashboard 显示分组节点列表。

### 16. 系统语言本地化实施计划

> **目标：** 将 Forge VPN 的应用界面接入 Flutter 官方本地化，支持简体中文和英文，其他系统语言回退英文。

**架构：** 使用 `flutter_localizations`、`l10n.yaml` 和中英文 ARB 资源生成 `AppLocalizations`。`MaterialApp` 跟随系统 Locale，页面通过 `AppLocalizations.of(context)` 获取固定界面文字；节点名称、机场备注和原始日志不翻译。

**约束：** 不修改 VPN 连接、节点解析、状态管理或订阅请求逻辑；不把 `BuildContext` 放进模型层；中文长文本必须在手机窄屏通过布局测试。

#### 任务 1：本地化基础配置和资源

**文件：** 修改 `pubspec.yaml`；新增 `l10n.yaml`、`lib/l10n/app_en.arb`、`lib/l10n/app_zh.arb`；新增 `test/localization_test.dart`。

- 先在测试中加载 `AppLocalizations.delegate`，验证 `Locale('zh')` 返回中文、`Locale('en')` 返回英文，`Locale('ja')` 使用英文资源回退。
- `app_en.arb` 和 `app_zh.arb` 至少覆盖导航、连接状态、首页指标、节点导入、设置、日志、节点状态和固定错误前缀。
- 在 `pubspec.yaml` 的 `flutter:` 下加入 `generate: true`，依赖加入 `flutter_localizations`。
- 运行 `flutter pub get` 和 `flutter gen-l10n`，确认生成的 `AppLocalizations` 可被测试导入。

#### 任务 2：应用入口和导航本地化

**文件：** 修改 `lib/main.dart`。

- `MaterialApp` 加入 `localizationsDelegates`、`supportedLocales: const [Locale('zh'), Locale('en')]` 和 `localeListResolutionCallback`，优先匹配中文，其余回退英文。
- 将 `_navItems` 从静态英文标签改为在 `build` 中用 `AppLocalizations` 创建，确保 BottomNavigationBar 与 NavigationRail 使用相同翻译。
- 将 AppBar 的 `Connected`、`Disconnected` 和品牌相关固定文字接入本地化。
- 保留现有响应式导航和 `IndexedStack` 行为。

#### 任务 3：首页文字本地化

**文件：** 修改 `lib/screens/dashboard_screen.dart`；扩展 `test/dashboard_responsive_test.dart`。

- 替换 `_StatusCard` 的无节点提示、连接状态相关固定文字。
- 替换 `_MetricsRow` 的 `Ping`、`Download`、`Upload` 标签。
- 替换 `_ServerTable` 的标题、`Check`、`Checking`、`available`、空列表提示、`Yes`、`No`、`Unknown`、`Connected`、`Ready` 等固定文字。
- 让测试在中文 Locale 下渲染首页，确认主要文字出现且无 `RenderFlex overflowed`。

#### 任务 4：节点、设置和日志页面本地化

**文件：** 修改 `lib/screens/nodes_screen.dart`、`lib/screens/settings_screen.dart`、`lib/screens/logs_screen.dart`；新增或扩展对应 widget 测试。

- 节点页替换 `Subscription URL`、`Import`、`Nodes`、`total`、空节点提示、导入成功/失败固定前缀。
- 设置页替换分组标题、路由模式、全局代理、智能分流、自动启动、深色模式和连接相关固定文字；保留设置值和保存逻辑。
- 日志页替换诊断按钮、空日志提示和固定状态文字；日志内容保持原样。
- 协议名通过页面侧本地化映射显示，`VpnNode` 数据模型不依赖 Locale。

#### 任务 5：完整验证和文档记录

**文件：** 修改 `PROJECT_SUMMARY.md`；必要时调整本地化测试。

- 运行 `flutter test test/localization_test.dart test/dashboard_responsive_test.dart`。
- 运行 `flutter analyze`，确认没有未生成的本地化 getter、未使用导入或类型错误。
- 由开发者执行 `flutter build apk --debug`，安装后在雷电模拟器切换中文/英文系统语言并重启验证。
- 记录实际构建和模拟器验证结果到本节，不新增设计文档。
### 18. Android parity implementation plan (2026-08-03)

> Goal: bring the user-visible Windows/iOS iteration capabilities that are safe and meaningful on Android into the existing Flutter/libbox architecture. Windows-only system proxy/tray behavior and iOS-only NetworkExtension signing details remain platform-specific.

#### Files and responsibilities

- `android/app/src/main/kotlin/com/example/forge_vpn_flutter/VpnStateStore.kt`: persist and expose the last Android VPN state/message so Flutter can restore a truthful state after activity recreation.
- `android/app/src/main/kotlin/com/example/forge_vpn_flutter/VpnBridge.kt`: return a richer Android diagnostic snapshot and clear stale state on service death/disconnect.
- `android/app/src/main/kotlin/com/example/forge_vpn_flutter/LibboxPlatformInterface.kt`: track the physical default interface, react to connectivity changes, and notify libbox when the network changes.
- `android/app/src/main/kotlin/com/example/forge_vpn_flutter/LibboxServiceController.kt`: expose command-server/service/TUN lifecycle diagnostics and close resources deterministically.
- `android/app/src/main/kotlin/com/example/forge_vpn_flutter/ForgeVpnService.kt`: report service start/stop/failure paths consistently.
- `lib/services/android_vpn_service.dart`: normalize the richer native diagnostic/state response for Flutter.
- `lib/providers/app_provider.dart`: restore Android state without stale connected UI, cancel checks on disconnect, and use an Android-safe health status policy.
- `test/android_diagnostics_test.dart`: pure Dart regression tests for diagnostic normalization and stale-state handling.
- `android/app/src/test/.../VpnStateStoreTest.kt`: native state/cleanup regression tests.

#### Execution tasks

1. Write failing tests for diagnostic normalization, persisted state reset, and network-change callback behavior.
2. Add native Android diagnostic fields: `serviceRunning`, `tunEstablished`, `commandServerReady`, `defaultInterface`, `interfaces`, `lastError`, SDK/device ABI, and the complete state snapshot.
3. Add a `ConnectivityManager.NetworkCallback` owned by `LibboxPlatformInterface`; publish the new physical interface to libbox on availability/loss and emit a log entry so DNS/network recovery is observable.
4. Make service stop/error paths close the command server and TUN, update `VpnStateStore`, and emit one terminal Flutter status instead of leaving `connecting` forever.
5. Add Dart-side normalization and state guards; disconnect cancels health workers and Android startup checks do not label a node unavailable solely because raw TCP bypassed the active proxy chain.
6. Run focused native/Dart tests and `git diff --check`; the developer runs Flutter analyze/build/APK and emulator verification locally.

#### Developer verification

- `flutter test test/android_diagnostics_test.dart`
- `flutter analyze`
- `flutter build apk --debug`
- `adb install -r build/app/outputs/flutter-apk/app-debug.apk`
- Emulator: connect, rotate/reconnect network, open Logs → Check VPN, disconnect, force-stop/reopen, and confirm restored state is not falsely connected.
- [ ] Google 账号扫码验证仍需专项域名诊断和跨设备出口一致性验证。
### 19. 近期迭代与实机验证记录（2026-07-31 ～ 2026-08-03）

#### 智能分流规则升级

- 移除原先手工维护的 `.cn` 泛域名直连规则，避免误把 `google.cn` 等域名强制直连。
- 智能分流改用 SagerNet 官方规则集：`geosite-cn`（中国域名）和 `geoip-cn`（中国 IP）。
- 规则集使用远程二进制格式，并通过代理下载；启用 sing-box 缓存，避免每次启动重复下载。
- DNS 与路由规则保持一致：中国域名/中国 IP 直连，其余流量走代理。
- 已增加回归测试，确认规则集中同时包含中国域名和中国 IP，且不再生成 `.cn` 泛规则。
- 实机日志确认：智能分流时微信相关域名（如 `mmbiz.qpic.cn`、`c2c.cdn.weixin.qq.com`）命中规则集并走直连；全局代理时微信上传会经过代理，受节点对国内 CDN 长连接或上传链路支持影响，可能失败。

#### iOS 真机 VPN 与签名

- 完成主应用与 Packet Tunnel 扩展的 App ID、Network Extensions、Personal VPN 能力配置。
- 完成 Ad Hoc 主应用描述文件和 Tunnel 描述文件的重新生成、签名和 IPA 打包。
- 修复 Libbox gomobile API 与 sing-box v1.13.x 的 Swift 接口变更，包括平台接口、命令服务、系统代理状态和通知接口。
- 修复 Libbox.framework 浅层 Bundle 的 `Info.plist`、扩展签名和嵌入问题。
- iPhone 真机已验证：VPN 配置可安装、隧道可启动、状态可进入 Connected，并能看到 sing-box TUN 流量日志。

#### 移动端界面与状态持久化

- 订阅地址卡片支持折叠；导入节点后可收起，减少首页占用空间。
- 输入订阅地址后自动收起键盘；Android 与 iOS 共用 Flutter 行为。
- 日志页增加导出按钮，可导出当前诊断日志供问题定位。
- 路由模式（智能分流/全局代理）写入本地持久化，应用退出后不会自动恢复成全局代理。
- 节点、订阅、选中节点和日志诊断状态继续使用本地缓存恢复，减少重启后状态丢失。

#### Google 验证与微信上传问题定位

- 实机对比确认：微信在智能分流下可正常发送文件，全局代理下可能失败；优先建议微信使用智能分流。
- YouTube 播放流畅但 Google 扫码验证失败，说明普通代理链路可用，问题更可能与 Google 认证所需的稳定出口 IP、Cookie、设备时间、DNS/TLS 长连接或跨设备出口不一致有关。
- 当前导出日志没有完整捕获 Google 认证域名，不能仅凭日志修改 Google 专用路由；后续诊断需记录 `accounts.google.com`、`gstatic.com`、`googleapis.com`、`googleusercontent.com` 和 YouTube 认证请求的 DNS、TCP、TLS 与最终路由。
- 远程 DoT 曾出现 `read response: EOF` 后重试成功，已记录为节点/DNS 稳定性观察项，不直接判定为规则集错误。

#### 当前实机验证结论

- [x] iOS Packet Tunnel 能安装并建立连接。
- [x] 智能分流下中国域名和中国 IP 命中官方规则集并直连。
- [x] 智能分流下微信文件发送验证通过。
- [ ] Google 账号扫码验证仍需专项域名诊断和跨设备出口一致性验证。
- [ ] 全局代理下微信上传不作为目标模式，需避免将其与智能分流能力混淆。
- [x] Android parity pass: native diagnostics now include service/TUN/command-server state, physical interface details, SDK/ABI, and the latest error message.
- [x] Android libbox default-interface monitoring now follows connectivity availability/loss events and asks libbox to refresh DNS/interface state.
- [x] Android terminal cleanup resets stale connected state and Flutter cancels in-flight node checks on disconnect; diagnostic responses are normalized defensively in Dart.
- [ ] Flutter/Android build and emulator verification remain developer-run because local Gradle/Flutter processes can block in this environment.

### 20. Windows 端近期迭代记录（2026-07-30 ～ 2026-08-03）

#### Windows 与移动端功能同步

- Windows 端保持与移动端一致的功能内容，同时采用桌面窗口、侧边导航和节点表格布局。
- 支持全局代理和智能分流，系统代理会在连接、断开和退出时自动设置或清理。
- 支持托盘后台运行，关闭窗口不再直接结束后台服务。
- 启动时恢复订阅、节点和选中节点，并自动执行一次节点检查。
- Windows 端会自动发现 Release 目录、应用目录和常用目录中的 `sing-box.exe`。

#### 订阅与协议

- 支持 HTTPS 订阅地址、Stash 安装链接和复制粘贴导入。
- 修复订阅输入期间 provider 更新覆盖输入内容的问题。
- 已导入订阅卡片默认折叠，点击标题展开；键盘完成会导入订阅、收起键盘和卡片。
- 支持 VMess、VLESS、Trojan、Shadowsocks、Hysteria2、AnyTLS 和 WireGuard。
- AnyTLS 保留 SNI、证书校验、会话检查间隔和最小空闲会话数等字段。
- 订阅节点、选中节点和路由模式会持久化，重启后恢复。

#### 节点健康检查与延迟

- Windows 检查会启动临时 sing-box，通过代理验证境外出口 IP，确认节点具备实际代理能力。
- 可用性验证与延迟显示分离，延迟使用节点服务器 TCP 握手时间，避免把出口 IP 查询耗时当成延迟。
- 每批检查使用固定节点快照，避免状态更新导致排序变化后跳过节点。
- 单节点超时 10 秒，整批超时 30 秒；超时节点会标记为不可用，不再永久停留在“检查中”。
- 启动检查异常会记录日志并清理残留的“检查中”状态。
- 已修复手动检查和启动检查中部分节点被漏检的问题。

#### 节点地区分组

- 支持地区代码前缀和英文国家名识别。
- 新增中文国家/地区名前缀识别：`日本-jpli`、`新加坡-sgli2`、`美国-us-vip-1`、`香港-hk-vip-1` 等会归入对应国家卡片。
- 同时支持 `韓國`、`臺灣`、`英國` 等繁体写法；无法识别的节点归入“其他”。

#### Windows 图标与安装发布

- Windows 图标替换为“锻造火花 + F”几何标志，避免与 FlClash 的蓝色折线图标混淆。
- 新增 `installer/forge-vpn.iss` 和 `scripts/build_windows_installer.ps1`。
- 安装包包含 Flutter Release 文件、`sing-box.exe` 和 `data` 目录，支持开始菜单、桌面快捷方式及卸载。
- Release 输出目录为 `dist/`，已加入 `.gitignore`。
- GitHub 仓库：`https://github.com/luolihao-ios/iPhoneVpnclient`。
- Windows Release：`v0.1.1-windows`，安装包为 `ForgeVPN-Setup-0.1.1.exe`；旧版 `v0.1.0-windows` 保留下载。

#### 本轮验证

- `flutter analyze lib/providers/app_provider.dart`：通过。
- `flutter analyze lib/core/node_grouping.dart`：通过。
- `flutter test test/singbox_service_test.dart`：通过。
- `flutter test test/node_grouping_test.dart`：通过。
- `flutter build windows --release`：通过。
- Inno Setup 成功生成 Windows 安装包并上传 GitHub Release。

### 21. AnyTLS iOS 诊断埋点与移动端布局调整（2026-08-04）

- iOS Packet Tunnel 启动时记录脱敏的 AnyTLS 配置摘要：服务器、端口、SNI、证书校验开关和密码长度，不记录密码内容。
- 诊断接口额外返回结构化 `configSummary`，不受 300 行滚动日志限制，导出日志可直接确认 AnyTLS、DNS 和路由配置是否进入 Tunnel 扩展。
- iOS 连接时固定使用 debug 级别，并记录路由模式；诊断摘要列出显式直连规则，结合 libbox 的 `router: match` 日志可定位境外 IP 被直连的具体原因。
- iOS 与 Android 两种模式统一使用稳定的本地 DNS；智能分流仍由“中国域名 + 中国 IP”规则集决定直连或代理，并对 Google/YouTube 等已识别的境外域名增加代理优先例外，避免规则集误判导致直连超时。
- 同时记录 DNS 最终服务器、DNS 服务器类型/代理链、路由最终出口和规则数量，用于区分节点参数错误、配置未传入扩展，以及 DNS/出站握手超时。
- Flutter 在 iOS 连接前记录选中 AnyTLS 节点的脱敏摘要，便于和 Packet Tunnel 日志逐项比对。
- iOS 与 Android 共用的 Flutter 外层内容增加顶部间距，并由 `SafeArea` 保护系统状态栏区域，首页及设置、日志等页面整体下移一个框的高度，避免内容贴近系统顶部区域。
- Flutter 测试与 iOS 真机构建由开发者在本机或 GitHub Actions 执行；本轮只提交源码和回归测试，不把本地超时视为通过。
- 手动运行 iOS GitHub Actions 时会创建带 IPA 附件的 GitHub Release；当前为 Ad Hoc 包，仅支持已注册 UDID 的设备，不能直接导入 TestFlight，越狱设备可按侧载工具支持安装。
