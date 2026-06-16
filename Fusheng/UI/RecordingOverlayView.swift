import SwiftUI

struct RecordingOverlayView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: coordinator.menuBarSystemImage)
                .font(.system(size: 32))

            Text(coordinator.statusText)
                .font(.headline)

            if !coordinator.latestPartialText.isEmpty {
                Text(coordinator.latestPartialText)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
