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
