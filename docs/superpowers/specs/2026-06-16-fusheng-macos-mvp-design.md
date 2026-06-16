# 浮声 macOS 端到端 MVP 设计

日期：2026-06-16

## 背景

浮声是一个 macOS 菜单栏语音输入工具。用户通过全局快捷键开始语音输入，App 完成录音、阿里百炼实时 ASR、文本整理，并根据当前系统焦点决定自动粘贴或保存为草稿。

本设计基于已有方案文档《浮声-macOS语音输入方案.md》，并收敛为第一版可开发 MVP。

## 已确认决策

- 第一版直接做真实端到端 MVP，不做纯 Mock 原型。
- 最低支持 macOS 14+。
- 在 `/Users/liudong/Documents/fushen` 创建原生 macOS Xcode 工程，并初始化 git 仓库。
- App 形态为 SwiftUI 菜单栏常驻应用，不做 Dock 主窗口。
- 同时支持两种录音触发方式：按一次开始/再按一次结束，以及按住说话/松开结束。
- 默认使用阿里百炼北京地域。
- 默认 ASR 模型为 `fun-asr-realtime`。
- 默认文本整理模型为 `qwen-plus`。
- API Key 保存到 macOS Keychain。
- 普通设置使用 `UserDefaults`。
- 草稿历史使用 SwiftData。
- 全局快捷键使用 Swift Package `KeyboardShortcuts`。

## 官方接口约束

阿里百炼 Fun-ASR 实时识别通过 WebSocket 接入。北京地域 WebSocket 端点为：

```text
wss://dashscope.aliyuncs.com/api-ws/v1/inference
```

WebSocket 握手请求头使用：

```text
Authorization: Bearer <api_key>
```

实时识别流程为：

1. 建立 WebSocket 连接。
2. 发送 `run-task` 指令。
3. 收到 `task-started` 后发送单声道音频二进制流。
4. 持续接收 `result-generated` 事件。
5. 录音结束后发送 `finish-task`。
6. 收到 `task-finished` 后关闭连接。

MVP 录音输出采用 16 kHz 单声道 PCM 音频块。文本整理使用百炼 OpenAI 兼容 Chat Completions 接口：

```text
POST https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions
```

MVP 不使用流式文本整理；录音结束并拿到最终 ASR 文本后，一次性请求整理结果。

参考文档：

- https://help.aliyun.com/zh/model-studio/fun-asr-realtime-websocket-api
- https://help.aliyun.com/zh/model-studio/asr-model/
- https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope

## 范围

### MVP 包含

- SwiftUI macOS 菜单栏 App。
- 设置页。
- API Key 输入、保存和读取。
- 全局快捷键配置。
- 切换式和按住式两种录音触发方式。
- 麦克风录音。
- DashScope WebSocket 实时 ASR。
- 百炼 Chat Completions 文本整理。
- Accessibility API 焦点检测。
- 剪贴板写入和模拟 `Command+V` 粘贴。
- 无输入焦点或输出失败时保存草稿。
- 草稿历史列表，支持复制、删除、重新整理、粘贴到当前焦点。
- 麦克风权限和辅助功能权限状态提示。

### MVP 暂不包含

- 上架包、签名、公证、自动更新。
- 多设备同步。
- 团队账号。
- 复杂模板系统。
- 读取 Figma、IDE、浏览器页面内容作为上下文。
- 语音命令系统。
- 热词管理。
- 本地 Whisper 或 Apple Speech 识别。
- 多地域自动切换。

## 架构

MVP 使用一个 `AppCoordinator` 管理主流程，UI 不直接操作网络、音频、权限或剪贴板。系统能力和网络接口都通过协议封装，以便单元测试和后续替换。

主要模块如下：

### MenuBar/UI

负责菜单栏状态、菜单项、设置页、草稿历史页和录音浮层。

菜单栏展示当前状态：

- 空闲
- 录音中
- 识别中
- 整理中
- 已粘贴
- 已保存草稿
- 错误

### AppCoordinator

负责串联完整状态机和错误分支。它依赖各服务协议，不直接包含具体实现细节。

### SettingsStore

保存普通设置：

- ASR 模型名
- 文本整理模型名
- 触发方式
- 默认整理模式
- 是否自动粘贴
- 是否恢复剪贴板
- 是否保留历史草稿
- 全局快捷键配置

普通设置使用 `UserDefaults`。API Key 不进入该模块。

### KeychainService

只负责保存、读取和删除阿里百炼 API Key。API Key 不写入日志、普通配置、草稿或错误文本。

### HotkeyService

负责注册和监听全局快捷键。MVP 使用 Swift Package `KeyboardShortcuts`，以便支持用户自定义快捷键，并同时监听 key down 和 key up 来实现切换式与按住式触发。

需要支持两种模式：

- Toggle：按一次开始录音，再按一次结束录音。
- Hold：按下开始录音，松开结束录音。

### AudioRecorder

使用 `AVAudioEngine` 采集麦克风音频，并转换为 16 kHz 单声道 PCM 音频块。模块对外提供异步音频块流。

需要处理：

- 麦克风权限不足。
- 麦克风设备不可用。
- 录音中断。
- 音频格式转换失败。

### DashScopeASRClient

负责连接 DashScope WebSocket，发送控制事件和音频二进制流，解析服务端事件，并输出最终 ASR 文本。

该模块不做录音、不做文本整理、不做 UI 状态管理。

### TextPolishClient

负责调用百炼 OpenAI 兼容 Chat Completions 接口，将原始 ASR 文本整理为可直接使用的文本。

支持整理模式：

- 原文：保留口语表达，仅补齐必要标点。
- 整理：去除明显口头禅和重复，适合聊天、文档输入。
- 专业：更适合需求、技术说明、会议纪要。
- 简短：压缩为更短表达。

### FocusDetector

使用 macOS Accessibility API 检测当前系统焦点是否为可输入文本控件。

判断依据是当前 focused element，而不是鼠标位置。

### TextInsertionService

默认使用剪贴板写入加模拟 `Command+V` 的方式输入文本。

流程：

1. 可选保存当前剪贴板内容。
2. 写入整理后的文本。
3. 模拟 `Command+V`。
4. 根据设置延迟恢复原剪贴板。

### DraftStore

保存未能自动输入或用户主动保存的语音结果。

草稿历史使用 SwiftData 本地持久化。

草稿字段：

- id
- 整理文本
- 原始 ASR 文本
- 创建时间
- 来源 App
- 整理模式
- 输出状态
- 错误摘要

## 状态机

主流程状态为：

```text
idle -> recording -> recognizing -> polishing -> delivering -> idle
```

错误状态为：

```text
failed
```

失败后尽量保存已有文本：

- 没有 API Key：不开始录音，提示配置。
- 麦克风权限不足：不开始录音，提示授权。
- 辅助功能权限不足：允许录音和识别，但输出阶段保存草稿并提示授权。
- ASR 失败且没有识别文本：保存错误，不创建空草稿。
- ASR 有文本但整理失败：保存原始 ASR 文本为草稿。
- 整理成功但粘贴失败：保存整理文本为草稿。
- 当前无可输入焦点：保存整理文本为草稿。

## 端到端流程

1. 用户触发全局快捷键。
2. `AppCoordinator` 检查 API Key、麦克风权限和当前状态。
3. `AudioRecorder` 开始输出 PCM 音频块。
4. `DashScopeASRClient` 建立 WebSocket 连接并发送 `run-task`。
5. 收到 `task-started` 后向 WebSocket 发送音频二进制流。
6. 用户再次触发快捷键或松开快捷键，录音结束。
7. 客户端发送 `finish-task`。
8. 收到最终 ASR 文本。
9. `TextPolishClient` 调用 `qwen-plus` 整理文本。
10. `FocusDetector` 检测当前 focused element。
11. 若可输入且自动粘贴开启，`TextInsertionService` 粘贴文本。
12. 若不可输入或粘贴失败，`DraftStore` 保存草稿。
13. 菜单栏和浮层显示最终状态。

## UI 设计

### 菜单栏菜单

菜单包含：

- 当前状态。
- 开始/停止录音。
- 最近 5 条草稿，点击复制。
- 打开草稿历史。
- 打开设置。
- 退出。

### 录音浮层

录音浮层为小型无焦点窗口，不抢占当前输入框焦点。

显示内容：

- 录音状态。
- 录音计时。
- 当前 ASR 片段或“正在整理”。
- 错误摘要。

### 设置页

设置页包含：

- API Key 输入和保存。
- ASR 模型名，默认 `fun-asr-realtime`。
- 文本整理模型名，默认 `qwen-plus`。
- 全局快捷键设置。
- 触发方式：切换式或按住式。
- 默认整理模式。
- 自动粘贴开关。
- 粘贴后恢复剪贴板开关。
- 历史草稿保留开关。
- 麦克风权限状态和系统设置入口。
- 辅助功能权限状态和系统设置入口。

### 草稿历史页

草稿历史页支持：

- 搜索。
- 复制。
- 删除。
- 重新整理。
- 粘贴到当前焦点。

重新整理使用已保存的原始 ASR 文本，不重新录音。

## 数据与隐私

- API Key 只存 Keychain。
- 草稿默认仅本地保存。
- 日志不输出 API Key。
- 日志不默认输出完整语音文本。
- 设置页说明语音音频和文本会发送到阿里百炼服务。
- MVP 不上传历史草稿到任何自有服务。

## 测试策略

### 单元测试

- 主状态机正常路径。
- 主状态机错误路径。
- ASR 服务端事件解析。
- 文本整理请求构造。
- 不同整理模式 prompt 生成。
- 草稿保存、删除、查询。
- 设置持久化。
- KeychainService 使用测试替身验证调用边界。

### 集成验证

- 使用真实 API Key 完成一次录音、ASR、文本整理。
- 输入框存在时自动粘贴。
- 输入框不存在时保存草稿。
- 辅助功能权限关闭时保存草稿。
- 粘贴后剪贴板恢复行为符合设置。

### 手动系统验证

- 首次启动权限引导。
- 两种快捷键触发方式。
- App 重启后设置保留。
- API Key 不出现在日志。
- 菜单栏退出后热键释放。

## 交付标准

第一版交付为可在本机 Xcode/Debug 运行的 macOS App。

完成标准：

- App 可启动并常驻菜单栏。
- 设置页可保存 API Key 和模型名。
- 两种快捷键触发方式可用。
- 能录音并调用阿里百炼实时 ASR。
- 能调用文本模型整理 ASR 结果。
- 有输入焦点时能自动粘贴。
- 无输入焦点时能保存草稿。
- 草稿历史可复制、删除、重新整理。
- 关键错误路径不丢已有文本。
- 核心状态机和请求构造有测试覆盖。

## 后续计划入口

本设计确认后，下一步使用 `superpowers:writing-plans` 生成实施计划。实施计划应按以下顺序拆分：

1. 工程初始化与基础架构。
2. 设置、Keychain、草稿存储。
3. 菜单栏 UI、设置页、草稿页。
4. 快捷键和录音状态机。
5. 音频采集和格式转换。
6. DashScope WebSocket ASR。
7. 文本整理接口。
8. 焦点检测和文本粘贴。
9. 端到端联调和测试。
