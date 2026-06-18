import SwiftData
import SwiftUI

struct DraftHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var drafts: [DraftRecord] = []
    @State private var searchText = ""
    @State private var deletionError: String?

    private var filteredDrafts: [DraftRecord] {
        guard !searchText.isEmpty else { return drafts }

        return drafts.filter {
            $0.polishedText.localizedCaseInsensitiveContains(searchText) ||
                $0.rawASRText.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack {
            TextField("搜索草稿", text: $searchText)
                .textFieldStyle(.roundedBorder)

            List {
                ForEach(filteredDrafts, id: \.id) { draft in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(draft.polishedText)

                        HStack(spacing: 8) {
                            Text(draft.createdAt.formatted())
                            Text(draft.deliveryStatus.displayText)
                            Text(draft.mode.displayName)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if !draft.rawASRText.isEmpty, draft.rawASRText != draft.polishedText {
                            Text(draft.rawASRText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        HStack {
                            Button("复制") {
                                copyToPasteboard(draft.polishedText)
                            }

                            Button("删除", role: .destructive) {
                                delete(draft)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding()
        .alert("删除失败", isPresented: deletionErrorBinding) {
            Button("好", role: .cancel) {
                deletionError = nil
            }
        } message: {
            Text(deletionError ?? "无法删除草稿")
        }
        .onAppear(perform: reloadDrafts)
        .onReceive(NotificationCenter.default.publisher(for: .draftHistoryDidChange)) { _ in
            reloadDrafts()
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var deletionErrorBinding: Binding<Bool> {
        Binding(
            get: { deletionError != nil },
            set: { isPresented in
                if !isPresented {
                    deletionError = nil
                }
            }
        )
    }

    private func delete(_ draft: DraftRecord) {
        modelContext.delete(draft)

        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .draftHistoryDidChange, object: nil)
            reloadDrafts()
        } catch {
            modelContext.rollback()
            deletionError = error.localizedDescription
        }
    }

    private func reloadDrafts() {
        do {
            let descriptor = FetchDescriptor<DraftRecord>(
                sortBy: [
                    SortDescriptor(\.createdAt, order: .reverse),
                    SortDescriptor(\.idSortKey, order: .reverse)
                ]
            )
            drafts = try modelContext.fetch(descriptor)
        } catch {
            deletionError = error.localizedDescription
        }
    }
}
