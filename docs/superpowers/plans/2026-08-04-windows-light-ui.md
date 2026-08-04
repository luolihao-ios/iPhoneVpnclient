# Windows 浅色桌面界面 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Windows 界面统一为蓝色顶部导航、浅蓝侧栏、白色内容区和清晰边框的桌面 UI。

**Architecture:** 保留现有页面和业务逻辑，只集中调整颜色令牌、Material 主题、桌面导航和页面组件样式。移动端继续使用底部导航，Windows 继续使用侧栏布局。

**Tech Stack:** Flutter、Material 3、Provider、现有响应式组件。

## Global Constraints

- 不修改代理、订阅、节点检查、托盘和 sing-box 业务逻辑。
- Windows 主内容区使用白色背景，不能保留大面积黑色卡片或黑色表头。
- 绿色只用于连接成功/可用状态；普通操作使用蓝色。
- 保持现有中文文案和响应式行为。

---

### Task 1: 统一颜色和 Material 主题

**Files:**
- Modify: `lib/widgets/responsive.dart`
- Modify: `lib/main.dart`
- Test: `test/dashboard_responsive_test.dart`

- [ ] 增加蓝色品牌色、浅蓝侧栏色、白色表面色和深色文字令牌。
- [ ] 将 Material 主题的 AppBar、NavigationRail、BottomNavigationBar、按钮和输入框默认色统一到新令牌。
- [ ] 运行 `flutter analyze lib/main.dart lib/widgets/responsive.dart`。

### Task 2: 重做桌面导航壳层

**Files:**
- Modify: `lib/main.dart`

- [ ] 桌面端增加蓝色顶部品牌栏和浅蓝侧栏。
- [ ] 当前导航使用蓝色高亮，未选中项使用深灰色。
- [ ] 保持手机端底部导航不变。
- [ ] 运行现有响应式测试，确认导航模式和路由保存行为不变。

### Task 3: 重做仪表盘卡片和节点表格

**Files:**
- Modify: `lib/screens/dashboard_screen.dart`
- Modify: `lib/widgets/subscription_import_card.dart`

- [ ] 节点状态卡片使用白底和突出边框，连接状态使用浅绿色背景。
- [ ] 延迟、下载、上传统计卡片使用白底和细分隔线。
- [ ] 订阅表格改为浅色表头、白色行、浅蓝分组标题和清晰行分隔线。
- [ ] 导入地址卡片和按钮统一到蓝色操作色。
- [ ] 运行 `flutter analyze lib/screens/dashboard_screen.dart lib/widgets/subscription_import_card.dart`。

### Task 4: 统一设置、日志和节点页面

**Files:**
- Modify: `lib/screens/settings_screen.dart`
- Modify: `lib/screens/logs_screen.dart`
- Modify: `lib/screens/nodes_screen.dart`

- [ ] 移除残留深色背景、深色表格和深色状态文字。
- [ ] 统一卡片边框、标题层级、按钮和下拉控件。
- [ ] 保持系统代理、版本显示和日志内容行为不变。
- [ ] 运行页面相关测试和 `flutter analyze`。

### Task 5: 回归验证和构建

- [ ] 运行 `flutter test`。
- [ ] 运行 `flutter analyze`。
- [ ] 运行 `flutter build windows --release`。
- [ ] 使用 `scripts/build_windows_installer.ps1` 生成安装包。
- [ ] 提交并推送实现改动。
