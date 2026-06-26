# Fusheng / 浮声

English | [中文](#中文)

Fusheng is a macOS voice input app. It records speech from the microphone, transcribes it with DashScope ASR, optionally polishes the text, and inserts the result into the currently focused text field.

## Features

- Global hotkey voice input for macOS.
- Live transcription preview while recording.
- Text polishing modes and per-mode strategy settings.
- Draft history for recent transcriptions.
- Failed recording recovery and retry flow.
- Clipboard-safe text insertion with tests for partial replacement edge cases.

## Requirements

- macOS 14 or later.
- Xcode 16 or later.
- A DashScope API key for speech recognition and text polishing.

## Build

Open `Fusheng.xcodeproj` in Xcode and run the `Fusheng` scheme.

If code signing fails on another machine, set your own Apple Development Team in Xcode under the app and test targets. The checked-in project is configured for local development builds.

You can also run the test suite from the command line:

```sh
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS'
```

## Local Install

For local development installs:

```sh
./script/publish_local.sh
```

This script runs tests, builds the app, installs it to `/Applications/浮声.app`, verifies the installed signature, and launches it.

## Configuration

The app stores the DashScope API key in the macOS Keychain. Do not commit real API keys or local `.env` files.

## License

MIT

---

## 中文

[English](#fusheng--浮声) | 中文

浮声是一款 macOS 语音输入应用。它会通过麦克风录制语音，使用 DashScope ASR 转写文字，可选择对文本进行整理润色，并把最终结果插入到当前聚焦的输入框中。

## 功能

- 支持 macOS 全局快捷键语音输入。
- 录音过程中显示实时转写预览。
- 支持多种文本整理模式，并可按模式配置整理策略。
- 保存近期转写结果到历史文稿。
- 支持失败录音恢复与重试。
- 提供剪贴板友好的文本插入逻辑，并包含针对输入框局部替换问题的测试。

## 环境要求

- macOS 14 或更高版本。
- Xcode 16 或更高版本。
- 用于语音识别和文本整理的 DashScope API Key。

## 构建

用 Xcode 打开 `Fusheng.xcodeproj`，运行 `Fusheng` scheme。

如果在其他机器上遇到代码签名失败，请在 Xcode 中为 App 和测试 Target 设置你自己的 Apple Development Team。当前提交的工程配置面向本地开发构建。

也可以通过命令行运行测试：

```sh
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS'
```

## 本地安装

本地开发安装可以运行：

```sh
./script/publish_local.sh
```

该脚本会运行测试、构建应用、安装到 `/Applications/浮声.app`、验证已安装应用签名，并启动应用。

## 配置

应用会把 DashScope API Key 存储在 macOS Keychain 中。不要提交真实 API Key 或本地 `.env` 文件。

## 许可证

MIT
