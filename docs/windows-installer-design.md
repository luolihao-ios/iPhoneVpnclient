# Forge VPN Windows 图标与安装包设计

## 目标

- 使用“锻造火花 + F”作为 Forge VPN 的 Windows 应用图标，避免与 FlClash 的蓝色折线图标混淆。
- 将 Flutter Release 目录（包括 sing-box 核心）制作成带卸载功能的 Windows 安装包。
- 安装包可作为 GitHub Release 的下载附件发布。

## 方案

- 图标资源统一使用 `windows/runner/resources/app_icon.ico`，由 Runner 和安装程序共同引用。
- 使用 Inno Setup 生成安装包，安装到 `Program Files/Forge VPN`，创建开始菜单和桌面快捷方式，并注册卸载入口。
- 安装程序从 `build/windows/x64/runner/Release` 读取完整运行目录，确保 `sing-box.exe` 与应用程序一起发布。

## 发布验收

- Release 构建成功，安装包可安装、启动和卸载。
- 安装后的应用图标、开始菜单快捷方式和桌面快捷方式均使用新图标。
- 安装目录包含 `forge_vpn_flutter.exe`、Flutter 运行库、`data` 目录和 `sing-box.exe`。
