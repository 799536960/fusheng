import AppKit
import SwiftUI

private enum RecordingOverlayMetrics {
    static let size = CGSize(width: 188, height: 72)
}

@MainActor
final class RecordingOverlayWindowController {
    static let shared = RecordingOverlayWindowController()

    private var panel: NSPanel?

    private init() {}

    func show(coordinator: AppCoordinator) {
        if panel == nil {
            let panel = NSPanel(
                contentRect: CGRect(origin: .zero, size: RecordingOverlayMetrics.size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.title = "录音状态"
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: RecordingOverlayView())
            self.panel = panel
        }

        positionPanel()
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel?.close()
        panel = nil
    }

    private func positionPanel() {
        guard let panel else { return }

        let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
        let size = RecordingOverlayMetrics.size
        let origin = CGPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + 72
        )

        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }
}

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

private struct AudioLevelWaveformView: View {
    let level: Double

    private let barCount = 8

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 5, height: barHeight(at: index))
                    .opacity(0.45 + level * 0.55)
            }
        }
    }

    private func barHeight(at index: Int) -> CGFloat {
        let phase = abs(Double(index) - Double(barCount - 1) / 2)
        let centerBoost = 1 - phase / Double(barCount)
        return CGFloat(6 + level * 28 * centerBoost)
    }
}
