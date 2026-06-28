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
            LogoRecordingMark()
                .frame(width: 38, height: 34)

            AudioLevelWaveformView(level: audioLevel)
                .frame(width: 104, height: 32)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: RecordingOverlayMetrics.size.width, height: RecordingOverlayMetrics.size.height)
        .background {
            LiquidGlassHUDBackground()
        }
        .shadow(color: Color(red: 0.02, green: 0.05, blue: 0.07).opacity(0.30), radius: 18, y: 8)
        .shadow(color: Color(red: 0.37, green: 0.93, blue: 0.92).opacity(0.14), radius: 18)
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

private struct LiquidGlassHUDBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.20),
                                Color(red: 0.07, green: 0.17, blue: 0.20).opacity(0.44),
                                Color(red: 0.02, green: 0.05, blue: 0.08).opacity(0.34),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.54),
                                Color(red: 0.65, green: 0.97, blue: 0.95).opacity(0.26),
                                Color.white.opacity(0.10),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    .blur(radius: 0.5)
                    .padding(1.5)
            )
    }
}

private struct LogoRecordingMark: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                AppLogoTailShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.43, green: 1.0, blue: 0.94).opacity(0.34),
                                Color(red: 0.08, green: 0.62, blue: 0.60).opacity(0.50),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color(red: 0.18, green: 0.92, blue: 0.88).opacity(0.24), radius: 5)

                AppLogoWaveShape()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.43, green: 1.0, blue: 0.94),
                                Color(red: 0.13, green: 0.84, blue: 0.80),
                                Color(red: 0.78, green: 1.0, blue: 0.96),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 7.2, lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: Color(red: 0.18, green: 0.92, blue: 0.88).opacity(0.34), radius: 5)

                AppLogoWaveShape()
                    .stroke(
                        Color.white.opacity(0.62),
                        style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round)
                    )
                    .offset(y: -2)
            }

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.56, blue: 0.30),
                            Color(red: 1.0, green: 0.27, blue: 0.13),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(Circle().stroke(Color.white.opacity(0.48), lineWidth: 0.7))
                .frame(width: 7.5, height: 7.5)
                .shadow(color: Color(red: 1.0, green: 0.45, blue: 0.22).opacity(0.42), radius: 4)
                .offset(x: -1.2, y: -1.5)
        }
        .accessibilityLabel("录音中")
    }
}

private struct AppLogoWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let minX = rect.minX
        let minY = rect.minY

        var path = Path()
        path.move(to: CGPoint(x: minX + width * 0.05, y: minY + height * 0.54))
        path.addCurve(
            to: CGPoint(x: minX + width * 0.24, y: minY + height * 0.42),
            control1: CGPoint(x: minX + width * 0.10, y: minY + height * 0.62),
            control2: CGPoint(x: minX + width * 0.16, y: minY + height * 0.30)
        )
        path.addCurve(
            to: CGPoint(x: minX + width * 0.43, y: minY + height * 0.23),
            control1: CGPoint(x: minX + width * 0.32, y: minY + height * 0.55),
            control2: CGPoint(x: minX + width * 0.32, y: minY + height * 0.12)
        )
        path.addCurve(
            to: CGPoint(x: minX + width * 0.61, y: minY + height * 0.62),
            control1: CGPoint(x: minX + width * 0.53, y: minY + height * 0.36),
            control2: CGPoint(x: minX + width * 0.47, y: minY + height * 0.72)
        )
        path.addCurve(
            to: CGPoint(x: minX + width * 0.79, y: minY + height * 0.48),
            control1: CGPoint(x: minX + width * 0.68, y: minY + height * 0.56),
            control2: CGPoint(x: minX + width * 0.70, y: minY + height * 0.37)
        )
        path.addCurve(
            to: CGPoint(x: minX + width * 0.95, y: minY + height * 0.52),
            control1: CGPoint(x: minX + width * 0.85, y: minY + height * 0.57),
            control2: CGPoint(x: minX + width * 0.89, y: minY + height * 0.58)
        )
        return path
    }
}

private struct AppLogoTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let minX = rect.minX
        let minY = rect.minY

        var path = Path()
        path.move(to: CGPoint(x: minX + width * 0.17, y: minY + height * 0.60))
        path.addCurve(
            to: CGPoint(x: minX + width * 0.46, y: minY + height * 0.70),
            control1: CGPoint(x: minX + width * 0.28, y: minY + height * 0.67),
            control2: CGPoint(x: minX + width * 0.36, y: minY + height * 0.70)
        )
        path.addCurve(
            to: CGPoint(x: minX + width * 0.38, y: minY + height * 0.92),
            control1: CGPoint(x: minX + width * 0.47, y: minY + height * 0.80),
            control2: CGPoint(x: minX + width * 0.43, y: minY + height * 0.87)
        )
        path.addCurve(
            to: CGPoint(x: minX + width * 0.66, y: minY + height * 0.72),
            control1: CGPoint(x: minX + width * 0.49, y: minY + height * 0.88),
            control2: CGPoint(x: minX + width * 0.58, y: minY + height * 0.78)
        )
        path.addCurve(
            to: CGPoint(x: minX + width * 0.82, y: minY + height * 0.60),
            control1: CGPoint(x: minX + width * 0.73, y: minY + height * 0.67),
            control2: CGPoint(x: minX + width * 0.77, y: minY + height * 0.62)
        )
        path.addLine(to: CGPoint(x: minX + width * 0.76, y: minY + height * 0.78))
        path.addCurve(
            to: CGPoint(x: minX + width * 0.17, y: minY + height * 0.60),
            control1: CGPoint(x: minX + width * 0.58, y: minY + height * 0.88),
            control2: CGPoint(x: minX + width * 0.35, y: minY + height * 0.82)
        )
        path.closeSubpath()
        return path
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
                                    Color.white.opacity(0.94),
                                    Color(red: 0.67, green: 1.0, blue: 0.98).opacity(0.96),
                                    Color(red: 0.18, green: 0.92, blue: 0.88).opacity(0.90),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(Capsule().stroke(Color.white.opacity(0.26), lineWidth: 0.5))
                        .shadow(color: Color(red: 0.18, green: 0.92, blue: 0.88).opacity(0.30), radius: 4)
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
