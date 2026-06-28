# Recording Overlay HUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current recording overlay with a smaller, more transparent icon-and-waveform HUD and improve audio-level response so speech creates visible waveform variation without immediate saturation.

**Architecture:** Keep the existing overlay lifecycle and notification pipeline. Update `RecordingOverlayView.swift` for the compact HUD and animated waveform, then update `AudioRecorder.swift` to publish a softer normalized audio level. Use source-level configuration tests for private SwiftUI layout and a direct unit test for the new audio-level normalizer.

**Tech Stack:** macOS SwiftUI, AppKit `NSPanel`, AVFoundation PCM audio, XCTest, existing Xcode project `Fusheng.xcodeproj`.

## Global Constraints

- The overlay must remain non-interactive and centered near the lower screen area.
- The overlay must not render preview text, partial transcript text, or status text.
- The HUD should be roughly 180-190 points wide and 68-76 points tall.
- The HUD should contain only a recording-state icon and an audio waveform.
- The waveform should vary per bar and avoid looking like one solid block.
- Normal speech should not immediately publish audio level `1.0`.
- The existing `.audioLevelDidChange` notification path and overlay visibility lifecycle must remain unchanged.
- Do not add new third-party dependencies.

---

## File Structure

- Modify `Fusheng/UI/RecordingOverlayView.swift`
  - Owns `RecordingOverlayWindowController`, the HUD SwiftUI view, the recording status icon, and waveform drawing.
  - Add a small private `RecordingOverlayMetrics` enum so the panel creation, positioning, and tests use one size.
  - Remove the generated microphone image factory because the new HUD uses a lightweight SwiftUI recording icon.

- Modify `Fusheng/Services/AudioRecorder.swift`
  - Keep capture and PCM conversion unchanged.
  - Add `AudioLevelNormalizer.normalizedLevel(rms:)` near `AudioRecorder`.
  - Use that normalizer in `publishAudioLevel(from:)`.

- Modify `FushengTests/AppBundleConfigurationTests.swift`
  - Update source snapshot tests for the compact icon-only HUD and staggered waveform implementation.

- Create `FushengTests/AudioLevelNormalizerTests.swift`
  - Directly tests the dB/soft-compression normalizer behavior through `@testable import Fusheng`.

---

### Task 1: Compact Icon-Only Recording HUD

**Files:**
- Modify: `FushengTests/AppBundleConfigurationTests.swift`
- Modify: `Fusheng/UI/RecordingOverlayView.swift`

**Interfaces:**
- Consumes: `Notification.Name.audioLevelDidChange`, `RecordingOverlayWindowController.show(coordinator:)`, existing `AppCoordinator` overlay lifecycle.
- Produces: `private enum RecordingOverlayMetrics { static let size = CGSize(width: 188, height: 72) }`, `private struct RecordingStatusIcon: View`, compact `RecordingOverlayView`.

- [ ] **Step 1: Write the failing test**

Replace `testRecordingOverlayUsesGeneratedMicrophoneImageAndWaveform` in `FushengTests/AppBundleConfigurationTests.swift` with:

```swift
func testRecordingOverlayUsesCompactIconOnlyHUD() throws {
    let source = try String(
        contentsOf: try sourceSnapshotURL("Fusheng/UI/RecordingOverlayView.swift"),
        encoding: .utf8
    )
    let appSource = try String(
        contentsOf: try sourceSnapshotURL("Fusheng/App/FushengApp.swift"),
        encoding: .utf8
    )

    XCTAssertTrue(source.contains("RecordingOverlayMetrics.size"))
    XCTAssertTrue(source.contains("CGSize(width: 188, height: 72)"))
    XCTAssertTrue(source.contains("RecordingStatusIcon"))
    XCTAssertTrue(source.contains("AudioLevelWaveformView"))
    XCTAssertTrue(source.contains(".audioLevelDidChange"))
    XCTAssertTrue(source.contains("configureFloatingOverlayWindow"))
    XCTAssertTrue(source.contains("panel.ignoresMouseEvents = true"))
    XCTAssertTrue(source.contains("window.ignoresMouseEvents = true"))
    XCTAssertTrue(source.contains(".ultraThinMaterial"))
    XCTAssertTrue(source.contains("RoundedRectangle(cornerRadius: 24"))
    XCTAssertFalse(source.contains("GeneratedMicrophoneImage"))
    XCTAssertFalse(source.contains("MicrophoneIconFactory"))
    XCTAssertFalse(source.contains("coordinator.statusText"))
    XCTAssertFalse(source.contains("latestPartialText"))
    XCTAssertFalse(source.contains("Text(coordinator"))
    XCTAssertFalse(appSource.contains("Window(\"录音状态\""))
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/AppBundleConfigurationTests/testRecordingOverlayUsesCompactIconOnlyHUD -quiet
```

Expected: FAIL because the current overlay still contains `GeneratedMicrophoneImage`, `coordinator.statusText`, `latestPartialText`, and `CGSize(width: 260, height: 108)`.

- [ ] **Step 3: Implement the compact HUD**

In `Fusheng/UI/RecordingOverlayView.swift`, add metrics near the top:

```swift
private enum RecordingOverlayMetrics {
    static let size = CGSize(width: 188, height: 72)
}
```

Update `RecordingOverlayWindowController.show(coordinator:)` panel creation:

```swift
let panel = NSPanel(
    contentRect: CGRect(origin: .zero, size: RecordingOverlayMetrics.size),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
```

Update `positionPanel()`:

```swift
let size = RecordingOverlayMetrics.size
let origin = CGPoint(
    x: visibleFrame.midX - size.width / 2,
    y: visibleFrame.minY + 72
)

panel.setFrame(CGRect(origin: origin, size: size), display: true)
```

Replace the `RecordingOverlayView` body with:

```swift
struct RecordingOverlayView: View {
    @State private var audioLevel = 0.08

    var body: some View {
        HStack(spacing: 14) {
            RecordingStatusIcon()
                .frame(width: 30, height: 30)

            AudioLevelWaveformView(level: audioLevel)
                .frame(width: 104, height: 30)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: RecordingOverlayMetrics.size.width, height: RecordingOverlayMetrics.size.height)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.11), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
        .onAppear(perform: configureFloatingOverlayWindow)
        .onReceive(NotificationCenter.default.publisher(for: .audioLevelDidChange)) { notification in
            let level = notification.userInfo?["level"] as? Double ?? 0.08
            withAnimation(.easeOut(duration: 0.12)) {
                audioLevel = max(0.04, min(0.96, level))
            }
        }
    }

    private func configureFloatingOverlayWindow() {
        DispatchQueue.main.async {
            NSApp.windows
                .filter { $0.title.contains("录音状态") }
                .forEach { window in
                    let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
                    let size = RecordingOverlayMetrics.size
                    let origin = CGPoint(
                        x: visibleFrame.midX - size.width / 2,
                        y: visibleFrame.minY + 72
                    )

                    window.setFrame(CGRect(origin: origin, size: size), display: true)
                    window.level = .floating
                    window.isOpaque = false
                    window.backgroundColor = .clear
                    window.hasShadow = false
                    window.ignoresMouseEvents = true
                    window.titleVisibility = .hidden
                    window.titlebarAppearsTransparent = true
                    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                }
        }
    }
}
```

Delete `GeneratedMicrophoneImage` and `MicrophoneIconFactory`.

Add the recording status icon before `AudioLevelWaveformView`:

```swift
private struct RecordingStatusIcon: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.16))

            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 1)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.25, blue: 0.22),
                            Color(red: 0.86, green: 0.02, blue: 0.08),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 12, height: 12)
                .shadow(color: .red.opacity(0.45), radius: 5)
        }
        .accessibilityLabel("录音中")
    }
}
```

- [ ] **Step 4: Run the focused test and verify it passes**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/AppBundleConfigurationTests/testRecordingOverlayUsesCompactIconOnlyHUD -quiet
```

Expected: PASS.

- [ ] **Step 5: Commit Task 1**

Run:

```bash
git add Fusheng/UI/RecordingOverlayView.swift FushengTests/AppBundleConfigurationTests.swift
git commit -m "feat: simplify recording overlay hud"
```

---

### Task 2: Staggered Animated Waveform

**Files:**
- Modify: `FushengTests/AppBundleConfigurationTests.swift`
- Modify: `Fusheng/UI/RecordingOverlayView.swift`

**Interfaces:**
- Consumes: `AudioLevelWaveformView(level: Double)` from Task 1.
- Produces: `AudioLevelWaveformView` with `TimelineView(.animation)`, stable per-bar weights, phase offsets, and clamped dynamic heights.

- [ ] **Step 1: Write the failing waveform test**

Add this test after `testRecordingOverlayUsesCompactIconOnlyHUD`:

```swift
func testRecordingOverlayWaveformUsesStaggeredAnimatedBars() throws {
    let source = try String(
        contentsOf: try sourceSnapshotURL("Fusheng/UI/RecordingOverlayView.swift"),
        encoding: .utf8
    )

    XCTAssertTrue(source.contains("TimelineView(.animation)"))
    XCTAssertTrue(source.contains("private let barWeights"))
    XCTAssertTrue(source.contains("private let phaseOffsets"))
    XCTAssertTrue(source.contains("let clampedLevel = max(0, min(1, level))"))
    XCTAssertTrue(source.contains("pow(clampedLevel, 0.72)"))
    XCTAssertTrue(source.contains("sin(phase + phaseOffsets[index])"))
    XCTAssertTrue(source.contains("max(7, min(26"))
    XCTAssertTrue(source.contains("barCount = 12"))
    XCTAssertFalse(source.contains("return CGFloat(6 + level * 28 * centerBoost)"))
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/AppBundleConfigurationTests/testRecordingOverlayWaveformUsesStaggeredAnimatedBars -quiet
```

Expected: FAIL because the current waveform uses 8 static bars and the old `level * 28 * centerBoost` formula.

- [ ] **Step 3: Implement staggered waveform rendering**

Replace `AudioLevelWaveformView` in `Fusheng/UI/RecordingOverlayView.swift` with:

```swift
private struct AudioLevelWaveformView: View {
    let level: Double

    private let barCount = 12
    private let barWeights: [Double] = [0.34, 0.48, 0.72, 0.56, 0.86, 0.64, 0.94, 0.58, 0.78, 0.52, 0.66, 0.40]
    private let phaseOffsets: [Double] = [0.0, 1.7, 3.1, 0.8, 2.6, 4.2, 1.1, 3.7, 5.0, 2.0, 4.7, 0.5]

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate * (2.6 + max(0, min(1, level)) * 3.2)

            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.90),
                                    Color.accentColor.opacity(0.86),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 3, height: barHeight(at: index, phase: phase))
                        .opacity(0.46 + max(0, min(1, level)) * 0.44)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func barHeight(at index: Int, phase: Double) -> CGFloat {
        let clampedLevel = max(0, min(1, level))
        let shapedLevel = pow(clampedLevel, 0.72)
        let motion = (sin(phase + phaseOffsets[index]) + 1) / 2
        let weightedLevel = shapedLevel * barWeights[index]
        let height = 7 + weightedLevel * 14 + motion * (1.5 + shapedLevel * 4.5)
        return CGFloat(max(7, min(26, height)))
    }
}
```

- [ ] **Step 4: Run the focused test and verify it passes**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/AppBundleConfigurationTests/testRecordingOverlayWaveformUsesStaggeredAnimatedBars -quiet
```

Expected: PASS.

- [ ] **Step 5: Commit Task 2**

Run:

```bash
git add Fusheng/UI/RecordingOverlayView.swift FushengTests/AppBundleConfigurationTests.swift
git commit -m "feat: animate recording waveform"
```

---

### Task 3: Softer Audio-Level Normalization

**Files:**
- Create: `FushengTests/AudioLevelNormalizerTests.swift`
- Modify: `Fusheng/Services/AudioRecorder.swift`

**Interfaces:**
- Consumes: PCM RMS values calculated in `AudioRecorder.publishAudioLevel(from:)`.
- Produces: `enum AudioLevelNormalizer { static func normalizedLevel(rms: Double) -> Double }`.

- [ ] **Step 1: Write the failing unit tests**

Create `FushengTests/AudioLevelNormalizerTests.swift`:

```swift
import XCTest
@testable import Fusheng

final class AudioLevelNormalizerTests: XCTestCase {
    func testNormalizerKeepsSilenceAtFloor() {
        XCTAssertEqual(AudioLevelNormalizer.normalizedLevel(rms: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(AudioLevelNormalizer.normalizedLevel(rms: -1), 0, accuracy: 0.0001)
        XCTAssertEqual(AudioLevelNormalizer.normalizedLevel(rms: .nan), 0, accuracy: 0.0001)
    }

    func testNormalizerDoesNotSaturateNormalSpeechLevels() {
        let quietSpeech = AudioLevelNormalizer.normalizedLevel(rms: 0.02)
        let normalSpeech = AudioLevelNormalizer.normalizedLevel(rms: 0.05)
        let strongSpeech = AudioLevelNormalizer.normalizedLevel(rms: 0.15)

        XCTAssertGreaterThan(quietSpeech, 0.10)
        XCTAssertGreaterThan(normalSpeech, quietSpeech)
        XCTAssertGreaterThan(strongSpeech, normalSpeech)
        XCTAssertLessThan(normalSpeech, 0.70)
        XCTAssertLessThan(strongSpeech, 0.92)
    }

    func testNormalizerIsMonotonicAndClamped() {
        let levels = [0.001, 0.005, 0.02, 0.05, 0.15, 0.4, 1.0]
            .map(AudioLevelNormalizer.normalizedLevel)

        XCTAssertEqual(levels, levels.sorted())
        XCTAssertGreaterThanOrEqual(levels.first ?? -1, 0)
        XCTAssertLessThanOrEqual(levels.last ?? 2, 0.96)
    }
}
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/AudioLevelNormalizerTests -quiet
```

Expected: FAIL because `AudioLevelNormalizer` does not exist.

- [ ] **Step 3: Implement the normalizer and use it**

Add this enum near the top of `Fusheng/Services/AudioRecorder.swift`, after imports:

```swift
enum AudioLevelNormalizer {
    static func normalizedLevel(rms: Double) -> Double {
        guard rms.isFinite, rms > 0 else { return 0 }

        let clampedRMS = min(max(rms, 0.000_01), 1)
        let decibels = 20 * log10(clampedRMS)
        let floorDecibels = -55.0
        let ceilingDecibels = -8.0
        let linearLevel = (decibels - floorDecibels) / (ceilingDecibels - floorDecibels)
        let clampedLevel = min(1, max(0, linearLevel))
        return min(0.96, pow(clampedLevel, 1.35) * 0.96)
    }
}
```

Update `publishAudioLevel(from:)`:

```swift
let rms = sqrt(sumSquares / Double(sampleCount))
let level = AudioLevelNormalizer.normalizedLevel(rms: rms)
Task { @MainActor in
    NotificationCenter.default.post(name: .audioLevelDidChange, object: nil, userInfo: ["level": level])
}
```

- [ ] **Step 4: Add source-level regression coverage for removing `rms * 8`**

Add this test to `FushengTests/AppBundleConfigurationTests.swift`:

```swift
func testAudioRecorderUsesSoftAudioLevelNormalization() throws {
    let source = try String(
        contentsOf: try projectFileURL("Fusheng/Services/AudioRecorder.swift"),
        encoding: .utf8
    )

    XCTAssertTrue(source.contains("enum AudioLevelNormalizer"))
    XCTAssertTrue(source.contains("static func normalizedLevel(rms: Double) -> Double"))
    XCTAssertTrue(source.contains("20 * log10(clampedRMS)"))
    XCTAssertTrue(source.contains("floorDecibels = -55.0"))
    XCTAssertTrue(source.contains("ceilingDecibels = -8.0"))
    XCTAssertTrue(source.contains("AudioLevelNormalizer.normalizedLevel(rms: rms)"))
    XCTAssertFalse(source.contains("rms * 8"))
}
```

- [ ] **Step 5: Run focused tests and verify they pass**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/AudioLevelNormalizerTests -only-testing:FushengTests/AppBundleConfigurationTests/testAudioRecorderUsesSoftAudioLevelNormalization -quiet
```

Expected: PASS.

- [ ] **Step 6: Commit Task 3**

Run:

```bash
git add Fusheng/Services/AudioRecorder.swift FushengTests/AudioLevelNormalizerTests.swift FushengTests/AppBundleConfigurationTests.swift
git commit -m "fix: soften recording audio level mapping"
```

---

### Task 4: Final Verification and Local Install

**Files:**
- Read: `Fusheng/UI/RecordingOverlayView.swift`
- Read: `Fusheng/Services/AudioRecorder.swift`
- Read: `FushengTests/AppBundleConfigurationTests.swift`
- Read: `FushengTests/AudioLevelNormalizerTests.swift`

**Interfaces:**
- Consumes: commits from Tasks 1-3.
- Produces: verified local `/Applications/浮声.app` build with compact recording HUD behavior.

- [ ] **Step 1: Run whitespace check**

Run:

```bash
git diff --check
```

Expected: exit 0 with no output.

- [ ] **Step 2: Run full test suite**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -quiet
```

Expected: exit 0. Existing Xcode destination warnings are acceptable.

- [ ] **Step 3: Build, install, and launch local app**

Run:

```bash
./script/build_and_run.sh --verify --skip-tests
```

Expected: build succeeds, `/Applications/浮声.app` is installed, signature verification passes, and one running process is printed.

- [ ] **Step 4: Confirm background-only app mode remains intact**

Run:

```bash
osascript -e 'tell application "System Events" to get background only of process "Fusheng"'
```

Expected:

```text
true
```

- [ ] **Step 5: Inspect final repository state**

Run:

```bash
git status --short --branch
git log --oneline --decorate -5
```

Expected: branch contains the task commits and no uncommitted implementation files.

---

## Self-Review

- Spec coverage: Task 1 covers the compact, transparent, text-free HUD. Task 2 covers per-bar waveform variation and visible motion. Task 3 covers softer audio normalization. Task 4 covers full tests and local install.
- Placeholder scan: no placeholder steps remain; each step has exact files, code, commands, and expected outcomes.
- Type consistency: `RecordingOverlayMetrics.size`, `RecordingStatusIcon`, `AudioLevelWaveformView(level:)`, and `AudioLevelNormalizer.normalizedLevel(rms:)` are introduced before use.
