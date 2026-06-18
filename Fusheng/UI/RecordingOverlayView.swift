import AppKit
import SwiftUI

@MainActor
final class RecordingOverlayWindowController {
    static let shared = RecordingOverlayWindowController()

    private var panel: NSPanel?

    private init() {}

    func show(coordinator: AppCoordinator) {
        if panel == nil {
            let panel = NSPanel(
                contentRect: CGRect(x: 0, y: 0, width: 260, height: 108),
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
            panel.contentView = NSHostingView(rootView: RecordingOverlayView().environmentObject(coordinator))
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
        let size = CGSize(width: 260, height: 108)
        let origin = CGPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + 72
        )

        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }
}

struct RecordingOverlayView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var audioLevel = 0.08

    var body: some View {
        HStack(spacing: 12) {
            GeneratedMicrophoneImage()
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 6) {
                Text(coordinator.statusText)
                    .font(.headline)

                AudioLevelWaveformView(level: audioLevel)
                    .frame(width: 96, height: 24)

                if !coordinator.latestPartialText.isEmpty {
                    Text(coordinator.latestPartialText)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
        .padding(12)
        .onAppear(perform: configureFloatingOverlayWindow)
        .onReceive(NotificationCenter.default.publisher(for: .audioLevelDidChange)) { notification in
            let level = notification.userInfo?["level"] as? Double ?? 0.08
            withAnimation(.easeOut(duration: 0.08)) {
                audioLevel = max(0.06, min(1, level))
            }
        }
    }

    private func configureFloatingOverlayWindow() {
        DispatchQueue.main.async {
            NSApp.windows
                .filter { $0.title.contains("录音状态") }
                .forEach { window in
                    let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
                    let size = CGSize(width: 260, height: 108)
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

private struct GeneratedMicrophoneImage: View {
    private static let image = MicrophoneIconFactory.makeImage()

    var body: some View {
        Image(nsImage: Self.image)
            .resizable()
            .interpolation(.high)
            .accessibilityLabel("麦克风")
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

private enum MicrophoneIconFactory {
    static func makeImage() -> NSImage {
        let size = CGSize(width: 256, height: 256)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let background = NSBezierPath(roundedRect: NSRect(x: 24, y: 24, width: 208, height: 208), xRadius: 58, yRadius: 58)
        NSColor(calibratedRed: 0.12, green: 0.44, blue: 0.96, alpha: 1).setFill()
        background.fill()

        let highlight = NSBezierPath(ovalIn: NSRect(x: 58, y: 154, width: 94, height: 58))
        NSColor(calibratedWhite: 1, alpha: 0.20).setFill()
        highlight.fill()

        let micBody = NSBezierPath(roundedRect: NSRect(x: 92, y: 82, width: 72, height: 104), xRadius: 34, yRadius: 34)
        NSColor.white.setFill()
        micBody.fill()

        let grille = NSBezierPath()
        grille.lineWidth = 7
        grille.lineCapStyle = .round
        NSColor(calibratedRed: 0.12, green: 0.44, blue: 0.96, alpha: 0.55).setStroke()
        for x in stride(from: 110, through: 146, by: 18) {
            grille.move(to: CGPoint(x: x, y: 112))
            grille.line(to: CGPoint(x: x, y: 158))
        }
        grille.stroke()

        let stem = NSBezierPath()
        stem.lineWidth = 14
        stem.lineCapStyle = .round
        NSColor.white.setStroke()
        stem.move(to: CGPoint(x: 128, y: 70))
        stem.line(to: CGPoint(x: 128, y: 48))
        stem.stroke()

        let base = NSBezierPath()
        base.lineWidth = 13
        base.lineCapStyle = .round
        base.move(to: CGPoint(x: 92, y: 46))
        base.line(to: CGPoint(x: 164, y: 46))
        base.stroke()

        let arc = NSBezierPath()
        arc.lineWidth = 12
        arc.lineCapStyle = .round
        arc.appendArc(
            withCenter: CGPoint(x: 128, y: 96),
            radius: 54,
            startAngle: 205,
            endAngle: 335
        )
        arc.stroke()

        return image
    }
}
