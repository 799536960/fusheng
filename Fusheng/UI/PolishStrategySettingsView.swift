import SwiftUI

struct PolishStrategySettingsView: View {
    @State private var settings = SettingsStore()
    @State private var selectedMode: TextPolishMode = .clean
    @State private var strategy = TextPolishStrategy.default(for: .clean)
    @State private var statusMessage = ""
    @State private var testInput = ""
    @State private var testResult = ""
    @State private var isTesting = false
    @State private var activeTestID: UUID?
    @State private var pendingReset: ResetScope?
    @State private var isResetDialogPresented = false

    private let keychain = KeychainService()
    private let polisher = TextPolishClient()

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selectedMode) {
                ForEach(TextPolishMode.allCases) { mode in
                    Text(mode.displayName)
                        .tag(mode)
                }
            }
            .frame(minWidth: 160, idealWidth: 180)

            Divider()

            Form {
                Section("普通选项") {
                    Toggle("启用自定义策略", isOn: $strategy.isCustomEnabled)
                    Text("关闭时使用当前模式默认策略；打开后下面的普通选项、模式策略和额外约束会生效。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Group {
                        Toggle("删除明显口头禅", isOn: $strategy.removeFillerWords)
                        Toggle("删除无意义重复", isOn: $strategy.removeMeaninglessRepetition)
                        Toggle("修正明显错别字", isOn: $strategy.fixObviousTypos)
                        Toggle("补充自然标点", isOn: $strategy.addNaturalPunctuation)
                        Toggle("允许轻微润色", isOn: $strategy.allowLightPolish)

                        Picker("保守程度", selection: $strategy.conservatism) {
                            ForEach(TextPolishConservatism.allCases) { conservatism in
                                Text(conservatism.displayName)
                                    .tag(conservatism)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .disabled(!strategy.isCustomEnabled)
                }

                Section("固定安全边界") {
                    Text(TextPolishPrompt.safetyBoundary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Section("模式策略") {
                    TextEditor(text: $strategy.modeInstruction)
                        .font(.body)
                        .frame(minHeight: 120)
                        .disabled(!strategy.isCustomEnabled)
                }

                Section("额外约束") {
                    TextEditor(text: $strategy.extraInstructions)
                        .font(.body)
                        .frame(minHeight: 96)
                        .disabled(!strategy.isCustomEnabled)
                }

                Section("测试整理效果") {
                    TextEditor(text: $testInput)
                        .font(.body)
                        .frame(minHeight: 90)

                    HStack {
                        Button(isTesting ? "整理中..." : "测试整理效果") {
                            runTest()
                        }
                        .disabled(isTesting || testInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if !testResult.isEmpty {
                        Text(testResult)
                            .textSelection(.enabled)
                    }
                }

                Section {
                    HStack {
                        Button("保存策略") {
                            saveStrategy()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("恢复当前模式默认") {
                            pendingReset = .current
                            isResetDialogPresented = true
                        }

                        Button("恢复全部默认") {
                            pendingReset = .all
                            isResetDialogPresented = true
                        }
                    }

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .padding()
        }
        .navigationTitle("整理策略")
        .onAppear {
            selectedMode = settings.polishMode
            loadStrategy(for: settings.polishMode)
        }
        .onChange(of: selectedMode) { _, newMode in
            loadStrategy(for: newMode)
        }
        .confirmationDialog("恢复默认策略", isPresented: $isResetDialogPresented) {
            switch pendingReset {
            case .current:
                Button("恢复当前模式默认", role: .destructive) {
                    resetCurrentMode()
                }
            case .all:
                Button("恢复全部默认", role: .destructive) {
                    resetAllModes()
                }
            case nil:
                EmptyView()
            }

            Button("取消", role: .cancel) {}
        } message: {
            switch pendingReset {
            case .current:
                Text("将清除当前模式的自定义整理策略。")
            case .all:
                Text("将清除所有模式的自定义整理策略。")
            case nil:
                Text("请选择要恢复的策略范围。")
            }
        }
    }

    private func loadStrategy(for mode: TextPolishMode) {
        strategy = settings.polishStrategy(for: mode)
        statusMessage = ""
        testResult = ""
        isTesting = false
        activeTestID = nil
    }

    private func saveStrategy() {
        settings.savePolishStrategy(strategy, for: selectedMode)
        statusMessage = "\(selectedMode.displayName) 策略已保存"
    }

    private func resetCurrentMode() {
        settings.resetPolishStrategy(for: selectedMode)
        loadStrategy(for: selectedMode)
        statusMessage = "\(selectedMode.displayName) 已恢复默认"
    }

    private func resetAllModes() {
        settings.resetAllPolishStrategies()
        loadStrategy(for: selectedMode)
        statusMessage = "全部整理策略已恢复默认"
    }

    private func runTest() {
        let rawText = testInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else { return }

        isTesting = true
        let testID = UUID()
        activeTestID = testID
        statusMessage = ""
        testResult = ""

        let currentStrategy = strategy.normalized(for: selectedMode)
        let model = settings.polishModel.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                guard !model.isEmpty else {
                    throw AppError.polishFailed("整理模型为空")
                }

                guard let loadedAPIKey = try keychain.loadAPIKey() else {
                    throw AppError.missingAPIKey
                }

                let apiKey = loadedAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !apiKey.isEmpty else {
                    throw AppError.recorderFailed("请先在基础设置中保存 API Key")
                }

                let polishedText = try await polisher.polish(
                    rawText: rawText,
                    strategy: currentStrategy,
                    model: model,
                    apiKey: apiKey
                )

                await MainActor.run {
                    guard activeTestID == testID else { return }
                    testResult = polishedText
                    activeTestID = nil
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    guard activeTestID == testID else { return }
                    statusMessage = error.localizedDescription
                    activeTestID = nil
                    isTesting = false
                }
            }
        }
    }
}

private enum ResetScope: Identifiable {
    case current
    case all

    var id: String {
        switch self {
        case .current:
            return "current"
        case .all:
            return "all"
        }
    }
}
