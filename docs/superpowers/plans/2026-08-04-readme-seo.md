# README SEO 优化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 重写 Forge VPN 首页 README，并完善 GitHub 仓库元数据和可被搜索引擎理解的项目文档。

**Architecture:** README 作为首页入口，使用中文说明和英文技术关键词；`docs/` 提供安装、功能和发布记录的内部链接；GitHub Description 和 Topics 与 README 保持一致。

**Tech Stack:** Markdown、GitHub Releases、GitHub repository metadata、Flutter project documentation。

## Global Constraints

- 只描述项目当前已经实现的功能，不承诺未实现的 VPN 能力。
- 中文为主，同时保留 Windows VPN、Android VPN、iOS VPN、sing-box、VLESS、VMess、AnyTLS、Flutter VPN client 等英文搜索词。
- 下载链接必须指向现有 GitHub Release 页面或现有仓库文件。
- 不把订阅地址、服务器地址、密钥或个人信息写入公开文档。

---

### Task 1: 重写首页 README

**Files:**
- Modify: `README.md`

**Interfaces:**
- Produces: 面向 GitHub 访客和搜索引擎的项目首页，包含平台下载、功能、协议、安装、开发和 FAQ。

- [ ] **Step 1: 删除 Flutter 默认模板和乱码内容**

  删除 `A new Flutter project.`、Flutter Codelab 和默认 Cookbook 链接，保留项目真实信息。

- [ ] **Step 2: 写入 SEO 首页结构**

  使用以下一级结构：项目简介、下载、核心功能、支持协议、Windows 安装、Android/iOS 安装、开发环境、项目文档、FAQ、隐私安全与许可证。

- [ ] **Step 3: 添加中英文自然关键词**

  在简介和功能中自然出现 `Windows VPN client`、`Android VPN`、`iOS VPN`、`Flutter VPN client`、`sing-box GUI`、`VLESS`、`VMess`、`AnyTLS`、`smart routing` 和 `system proxy`。

- [ ] **Step 4: 添加真实下载入口和文档链接**

  Windows 链接指向 `v0.1.1-windows` Release，Android 链接指向 `v0.1.0-android` Release，iOS 链接指向 `ios-test-103` Release；同时链接 `PROJECT_SUMMARY.md` 和 `docs/recent-iterations.md`。

- [ ] **Step 5: 检查链接和 Markdown 结构**

  确认标题层级连续、链接可解析、没有乱码、没有个人订阅信息。

### Task 2: 增加可爬取的 SEO 文档入口

**Files:**
- Create: `docs/seo-keywords.md`
- Modify: `docs/recent-iterations.md`

**Interfaces:**
- Produces: 面向英文搜索用户的关键词摘要，以及 README 可访问的详细功能和版本文档。

- [ ] **Step 1: 创建英文关键词摘要**

  说明 Forge VPN 的平台、协议、路由模式和 sing-box 集成，使用完整句子而非关键词堆砌。

- [ ] **Step 2: 补充文档交叉链接**

  在最近迭代文档中加入 README、Release 和 SEO 摘要链接，形成稳定的内部链接结构。

- [ ] **Step 3: 检查文档内容一致性**

  确认平台名称、版本链接、协议列表和 Windows 功能与 README 及实际 Release 一致。

### Task 3: 完善 GitHub 仓库元数据

**Files:**
- External metadata: GitHub repository `luolihao-ios/iPhoneVpnclient`

**Interfaces:**
- Produces: 与 README 一致的仓库 Description 和 Topics。

- [ ] **Step 1: 更新仓库 Description**

  设置为：`Forge VPN：Windows、Android、iOS 多平台 VPN 客户端，基于 Flutter 与 sing-box，支持 VLESS、VMess、AnyTLS、Trojan、Shadowsocks、Hysteria2、WireGuard、全局代理和智能分流。`

- [ ] **Step 2: 设置 Topics**

  使用：`vpn`、`windows-vpn`、`android-vpn`、`ios-vpn`、`flutter`、`sing-box`、`vless`、`vmess`、`anytls`、`proxy`、`smart-routing`。

- [ ] **Step 3: 读取并核对元数据**

  使用 GitHub CLI 检查 Description 和 Topics 已生效，并确认仓库仍为公开状态。

### Task 4: 验证和提交

**Files:**
- Verify: `README.md`, `docs/seo-keywords.md`, `docs/recent-iterations.md`

- [ ] **Step 1: 检查 Markdown 关键内容**

  搜索平台关键词、协议关键词、Release 链接和 FAQ 标题，确认都存在且没有乱码。

- [ ] **Step 2: 检查 Git 状态**

  确认只包含本次 README/SEO 文档修改，没有构建产物或临时文件。

- [ ] **Step 3: 提交并推送**

  使用提交信息 `docs: optimize README and repository SEO`，推送到 `main`。
