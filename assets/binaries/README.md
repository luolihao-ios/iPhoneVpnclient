# sing-box 核心文件

移动端二进制按平台放在本目录。Windows 版本请从 sing-box 官方发布页获取对应的 x64 文件，并命名为：

`sing-box-windows-amd64.exe`

开发运行时可将它放在 Flutter 可执行文件旁边：

`build/windows/x64/runner/Release/sing-box.exe`

打包发布时也可以放在安装目录的 `data/flutter_assets/assets/binaries/` 下。应用会自动搜索这两个位置。
