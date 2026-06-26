# Fusheng

Fusheng (浮声) is a macOS voice input app. It records speech from the microphone, transcribes it with DashScope ASR, optionally polishes the text, and inserts the result into the currently focused text field.

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
