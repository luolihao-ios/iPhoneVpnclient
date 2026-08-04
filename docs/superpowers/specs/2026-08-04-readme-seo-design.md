# README 与仓库 SEO 优化设计

## 目标

提升 Forge VPN 在 GitHub 搜索和 Google 搜索中的可发现性，同时让首次访问者快速理解项目用途、支持平台、协议和下载方式。

## 内容策略

- README 采用中文为主、英文关键词并列的结构。
- 标题和首段明确包含：Windows VPN、Android VPN、iOS VPN、Flutter VPN client、sing-box GUI。
- 功能说明只写仓库已经实现的能力，避免夸大或堆砌关键词。
- 使用平台、协议、路由模式、节点检测和安装方式作为自然搜索词。

## README 结构

1. 项目标题、简介和平台徽章。
2. Windows、Android、iOS 下载入口。
3. 核心功能和支持协议。
4. Windows 安装说明。
5. Android/iOS 安装说明。
6. 运行与开发环境。
7. 项目文档和发布记录链接。
8. 常见问题（FAQ）。
9. 隐私、安全和许可证说明。

## 仓库元数据

- 更新 GitHub 仓库 Description，使其包含中英文核心关键词。
- 添加与项目实际能力匹配的 Topics，例如 `vpn`、`windows-vpn`、`sing-box`、`vless`、`anytls`、`flutter`。
- 保留公开仓库和 Releases，确保下载入口可被访问和分享。

## 配套 SEO 内容

- 新增一份英文关键词摘要，帮助非中文搜索用户理解项目。
- 在 `docs/` 中补充安装、功能和版本说明链接，形成可爬取的内部文档结构。
- README 使用稳定的 Markdown 标题层级、描述性链接文本和真实截图/发布链接。

## 验收标准

- README 不再包含 Flutter 默认模板或乱码。
- 用户在首页可直接找到三个平台的下载入口。
- README 明确列出主要协议、代理模式、节点检测和 Windows 托盘/代理清理能力。
- GitHub Description 和 Topics 与 README 关键词一致。
- 所有链接指向现有仓库文件或真实 Release 页面。
