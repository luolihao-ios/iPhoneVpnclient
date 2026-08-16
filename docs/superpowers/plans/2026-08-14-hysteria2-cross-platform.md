# Hysteria2 跨平台支持实施计划

> **执行方式：** 用户已授权直接在 `main` 修改；不创建额外工作区。

## 目标

让 Windows、Android 与 iOS 通过共享 Dart 代码导入 Clash YAML / sing-box JSON 中的 Hysteria2 节点，并生成可由各端现有 sing-box / libbox 运行时使用的配置。

## 任务 1：先建立失败测试

1. 新建 `test/hysteria2_support_test.dart`。
2. 覆盖 Clash YAML 中的 `type: hysteria2`：服务器、端口、密码、SNI、ALPN、跳过证书校验、混淆和带宽。
3. 覆盖 sing-box JSON outbound 的 Hysteria2：读取嵌套 TLS/obfs 字段。
4. 覆盖持久化往返与 `buildSingBoxConfig` 生成的 `hysteria2` outbound。
5. 先运行该测试，确认因缺少 `NodeType.hysteria2` / 映射而失败。

## 任务 2：扩展共享节点模型

1. 在 `NodeType` 增加 `hysteria2`，并补齐英文及本地化展示。
2. 在 `VpnNode` 增加 `obfs`、`alpn`、`upMbps`、`downMbps`。
3. 将新字段接入 `copyWith`、JSON 序列化与反序列化；Hysteria2 的最低可用条件为服务器、端口和密码。

## 任务 3：扩展订阅解析

1. 在 `_normalizeJsonNode` 中新增 `hysteria2` 分支，兼容 Clash 与 sing-box 常见字段名。
2. 在 `_singBoxOutboundToNode` 展平 `tls.alpn` 和 `obfs.password`。
3. 确保无法识别的单个节点仍由现有过滤逻辑跳过，不影响同一订阅中的有效节点。

## 任务 4：生成共享 sing-box 配置

1. 在 `_nodeToOutbound` 增加原生 `hysteria2` outbound。
2. 写入 `password`、可选 `up_mbps`/`down_mbps`、可选 salamander `obfs`，以及必需 TLS 配置。
3. 将 ALPN 保留在 TLS 中；不改动平台控制器，以共享的 `buildSingBoxConfig` 覆盖 Windows、Android、iOS。

## 任务 5：验证与交付

1. 运行新增测试、AnyTLS/订阅容错回归测试及静态检查。
2. 由用户构建 Windows、Android、iOS 安装包；通过后再提交、推送并更新既有三个 GitHub Release 的同一页面。
3. 版本升为 `0.1.5+1`，保留旧资产，并把本次迭代写入 Release body 和项目文档。

