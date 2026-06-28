# Recording Overlay HUD Design

## Goal

Improve the centered recording overlay so it feels lighter and more polished while staying purely functional. The overlay should no longer display preview or partial transcript text. It should communicate only the active recording state through a compact status icon and a responsive audio waveform.

## Scope

- Redesign `RecordingOverlayView` as a smaller floating HUD.
- Remove `coordinator.statusText` and `coordinator.latestPartialText` from the overlay UI.
- Keep the overlay non-interactive and centered near the lower screen area.
- Make the background more transparent and visually lighter than the current capsule.
- Improve audio-level mapping so normal speech does not immediately saturate the waveform.
- Improve waveform rendering so bars vary independently enough to show audible motion and intensity changes.

## UI Design

The overlay becomes a compact horizontal HUD, roughly 180-190 points wide and 68-76 points tall. It contains:

- A small recording status icon on the left, using a subtle active recording treatment.
- A waveform strip on the right, centered vertically.

The container uses a translucent material with a low-opacity border and softer shadow. The visual weight should be lower than the current `regularMaterial` capsule. No transcript, status label, or preview text appears inside the HUD.

## Audio Level Behavior

The recorder continues publishing `Notification.Name.audioLevelDidChange`, but the level calculation should use a less aggressive mapping than `rms * 8`. The preferred mapping is a dB-based normalization or soft compression curve that gives useful motion across quiet, normal, and loud speech without clipping too early.

The overlay clamps and animates incoming levels to avoid jitter while preserving visible changes. The waveform should keep some baseline movement at low levels and use per-bar phase differences so it does not look like one solid block.

## Implementation Notes

- `RecordingOverlayWindowController` should use the new smaller size in both panel creation and positioning.
- `RecordingOverlayView` should remove all preview text rendering.
- `AudioLevelWaveformView` can remain private to `RecordingOverlayView.swift`, but its bar-height formula should produce staggered heights from level plus stable per-bar weights.
- `AudioRecorder.publishAudioLevel(from:)` should publish normalized levels that rarely hit `1.0` during ordinary speech.
- The existing notification path and overlay visibility lifecycle should remain unchanged.

## Testing

Add or update tests to assert:

- The overlay source does not render `latestPartialText`, `coordinator.statusText`, or preview text.
- The overlay uses a smaller panel/frame size than the current `260x108`.
- The overlay still uses `AudioLevelWaveformView` and listens for `.audioLevelDidChange`.
- `AudioRecorder` no longer uses the `rms * 8` saturation mapping and includes a softer normalization path.

Run the focused tests first, then the full macOS test suite and the local build/run script.
