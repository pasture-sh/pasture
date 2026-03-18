import SwiftUI
import MarkdownUI
import SwiftData
#if os(iOS)
import UIKit
#endif

struct ChatView: View {
    @EnvironmentObject var connection: ConnectionManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @StateObject private var viewModel = ChatViewModel()
    @State private var isShowingSettings = false
    @State private var isShowingNewChatConfirmation = false
    @State private var chatEnvironment = ModelEnvironment.chat(for: nil)
    @State private var hasInitializedTheme = false

    var body: some View {
        ZStack(alignment: .top) {
            EnvironmentBackground(environment: backgroundEnvironment)
                .id(backgroundEnvironment.id)
                .transition(.opacity)

            if viewModel.isLoadingModels {
                LoadingModelsView(palette: backgroundEnvironment.palette)
            } else if viewModel.needsModelSetup {
                FirstModelSetupView(
                    models: CuratedModelLibrary.recommended,
                    installedModelNames: viewModel.installedModelNames,
                    activeDownload: viewModel.activeDownload,
                    errorMessage: viewModel.modelLoadError,
                    palette: ModelEnvironment.onboardingDefault.palette,
                    reduceTransparency: reduceTransparency,
                    isConnected: connection.isConnected,
                    onDownload: { model in
                        await viewModel.download(curatedModel: model, connection: connection)
                    },
                    onRefresh: {
                        await viewModel.loadModels(connection: connection)
                    }
                )
            } else if viewModel.shouldShowIntentPicker {
                IntentPickerView(
                    palette: ModelEnvironment.onboardingDefault.palette,
                    reduceTransparency: reduceTransparency
                ) { intent in
                    viewModel.chooseIntent(intent)
                }
            } else {
                chatContent
            }

            if shouldShowConnectionRecoveryBanner {
                ChatConnectionRecoveryBanner(
                    state: connection.state,
                    palette: chatPalette,
                    reduceTransparency: reduceTransparency
                ) {
                    Task { await connection.startDiscovery() }
                }
                .padding(.top, 64)
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .fontDesign(.rounded)
        .task {
            viewModel.bootstrapPersistence(modelContext: modelContext)
            await viewModel.loadModels(connection: connection)
            refreshChatEnvironment(modelName: viewModel.selectedModel?.name, animated: false)
        }
        .onChange(of: connection.installedModels) { _, newModels in
            viewModel.applyInstalledModels(newModels)
        }
        .onChange(of: viewModel.selectedModel?.name) { oldValue, newValue in
            let shouldAnimate = hasInitializedTheme && oldValue != nil && oldValue != newValue
            refreshChatEnvironment(modelName: newValue, animated: shouldAnimate)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            refreshChatEnvironment(modelName: viewModel.selectedModel?.name, animated: false)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: shouldShowConnectionRecoveryBanner)
        .sheet(isPresented: $isShowingSettings) {
            ChatSettingsView()
                .environmentObject(connection)
        }
        .confirmationDialog(
            "Start a new chat?",
            isPresented: $isShowingNewChatConfirmation,
            titleVisibility: .visible
        ) {
            Button("New Chat", role: .destructive) {
                viewModel.startNewChat()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the current conversation on this device.")
        }
    }

    private var isPreModelFlow: Bool {
        viewModel.isLoadingModels || viewModel.needsModelSetup || viewModel.shouldShowIntentPicker
    }

    private var backgroundEnvironment: ModelEnvironment {
        isPreModelFlow ? .onboardingDefault : chatEnvironment
    }

    private var chatPalette: EnvironmentPalette {
        chatEnvironment.palette
    }

    private var shouldShowConnectionRecoveryBanner: Bool {
        !isPreModelFlow && !connection.isConnected
    }

    private var chatContent: some View {
        VStack(spacing: 0) {
            topBarStrip

            if let modelLoadError = viewModel.modelLoadError {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 12, weight: .semibold))
                    Text(modelLoadError)
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(2)
                    Spacer()
                    Button("Retry") {
                        Task { await viewModel.loadModels(connection: connection) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(chatPalette.nearLayer.opacity(0.48), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 0.5)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(
                                message: message,
                                userBubbleColor: chatPalette.userBubble
                            )
                                .id(message.id)
                        }
                        if viewModel.isStreaming {
                            StreamingBubble(text: viewModel.streamingText)
                                .id("streaming")
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                    .padding(.horizontal, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: viewModel.streamingText) { _, _ in
                    withAnimation { proxy.scrollTo("streaming") }
                }
            }

            ComposeBar(
                palette: chatPalette,
                reduceTransparency: reduceTransparency,
                isDisabled: viewModel.isStreaming || viewModel.selectedModel == nil || !connection.isConnected
            ) { text in
                await viewModel.send(text: text, connection: connection)
            }
        }
    }

    @ViewBuilder
    private var topBarStrip: some View {
        let controls = HStack(spacing: 12) {
            if !viewModel.installedModels.isEmpty {
                ModelPickerChip(
                    models: viewModel.installedModels,
                    selectedModelName: viewModel.selectedModel?.name,
                    palette: chatPalette,
                    reduceTransparency: reduceTransparency
                ) { selected in
                    viewModel.selectModel(selected, userInitiated: true)
                }
            }

            Spacer()

            TopBarCircleButton(
                systemName: "square.and.pencil",
                palette: chatPalette,
                reduceTransparency: reduceTransparency,
                isEnabled: !viewModel.isStreaming
            ) {
                if viewModel.hasMessages {
                    isShowingNewChatConfirmation = true
                } else {
                    viewModel.startNewChat()
                }
            }

            TopBarCircleButton(
                systemName: "gearshape.fill",
                palette: chatPalette,
                reduceTransparency: reduceTransparency
            ) {
                isShowingSettings = true
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)

        if #available(iOS 26.0, *), !reduceTransparency {
            GlassEffectContainer(spacing: 12) {
                controls
            }
        } else {
            controls
        }
    }

    private func refreshChatEnvironment(modelName: String?, animated: Bool) {
        let updated = ModelEnvironment.chat(for: modelName)
        if animated {
            withAnimation(.easeInOut(duration: 0.8)) {
                chatEnvironment = updated
            }
        } else {
            chatEnvironment = updated
        }
        hasInitializedTheme = true
    }
}

struct ChatSettingsView: View {
    @EnvironmentObject var connection: ConnectionManager
    @Environment(\.dismiss) private var dismiss
    @State private var deletingModelName: String?
    @State private var pendingDeleteModel: OllamaModel?
    @State private var deleteErrorMessage: String?
    @State private var activeDownload: ModelDownloadState?
    @State private var downloadErrorMessage: String?
    @State private var downloadTask: Task<Void, Never>?
    @State private var isShowingDiagnostics = false
    @State private var copiedDiagnostics = false

    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 10, height: 10)
                        Text(statusText)
                            .font(.system(.body, design: .rounded))
                    }
                }

                Section("Advanced Diagnostics") {
                    DisclosureGroup("Connection runtime health", isExpanded: $isShowingDiagnostics) {
                        LabeledContent("Discovery starts", value: "\(connection.diagnostics.discoveryStarts)")
                        LabeledContent("Peer refreshes", value: "\(connection.diagnostics.peerRefreshes)")
                        LabeledContent("Visible peers", value: "\(connection.diagnostics.visiblePeerCount)")
                        LabeledContent("Visible helpers", value: "\(connection.diagnostics.visibleHelperCount)")
                        LabeledContent("Connect attempts", value: "\(connection.diagnostics.connectAttempts)")
                        LabeledContent("Connect successes", value: "\(connection.diagnostics.connectSuccesses)")
                        LabeledContent("Reconnect schedules", value: "\(connection.diagnostics.reconnectSchedules)")
                        LabeledContent("Reconnect exhausted", value: "\(connection.diagnostics.reconnectExhausted)")
                        LabeledContent("Disconnects", value: "\(connection.diagnostics.disconnects)")
                        LabeledContent("Requests sent", value: "\(connection.diagnostics.requestsSent)")
                        LabeledContent("Responses received", value: "\(connection.diagnostics.responsesReceived)")
                        LabeledContent("Decode failures", value: "\(connection.diagnostics.responseDecodeFailures)")
                        LabeledContent("Request timeouts", value: "\(connection.diagnostics.requestTimeouts)")
                        LabeledContent("Remote errors", value: "\(connection.diagnostics.remoteErrors)")
                        LabeledContent("Chat cancellations", value: "\(connection.diagnostics.chatStreamCancellations)")
                        LabeledContent("Pull cancellations", value: "\(connection.diagnostics.pullStreamCancellations)")

                        if let lastError = connection.diagnostics.lastError, !lastError.isEmpty {
                            Text(lastError)
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(.red)
                                .padding(.top, 4)
                        }

                        if let loomRuntimeError = connection.diagnostics.loomRuntimeError,
                           !loomRuntimeError.isEmpty {
                            Text("Loom runtime: \(loomRuntimeError)")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(.orange)
                                .padding(.top, 2)
                        }

                        if let peerSummary = connection.diagnostics.lastPeerSnapshotSummary,
                           !peerSummary.isEmpty {
                            Text(peerSummary)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }

                        if diagnosticsEvents.isEmpty {
                            Text("No diagnostic events yet.")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        } else {
                            ForEach(diagnosticsEvents) { event in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("[\(event.level.rawValue.uppercased())] \(formattedTimestamp(event.timestamp))")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(eventColor(for: event.level))
                                    Text(event.message)
                                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }

                        HStack {
                            Button("Clear diagnostics") {
                                connection.clearDiagnostics()
                                copiedDiagnostics = false
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Spacer()

                            Button(copiedDiagnostics ? "Copied" : "Copy") {
                                copyDiagnosticsToPasteboard()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .padding(.top, 4)
                    }
                }

                Section("Available Macs") {
                    if connection.availableHelpers.isEmpty {
                        Text("No Macs found right now.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(connection.availableHelpers) { peer in
                            Button {
                                Task { await connection.connectToHelper(peerID: peer.id) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(peer.name)
                                            .font(.system(.body, design: .rounded, weight: .semibold))
                                            .foregroundStyle(.primary)
                                        Text(peer.isNearby ? "Nearby" : "Reachable")
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if connection.connectedPeerID == peer.id {
                                        Text("Connected")
                                            .font(.system(.caption, design: .rounded, weight: .semibold))
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Get More Models") {
                    if !connection.isConnected {
                        Text("Reconnect to your Mac to download models.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    if availableRecommendedModels.isEmpty {
                        Text("All recommended models are already installed.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableRecommendedModels) { model in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.displayName)
                                        .font(.system(.body, design: .rounded, weight: .semibold))
                                    Text(model.description)
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button {
                                    startDownload(model)
                                } label: {
                                    if activeDownload?.modelID == model.id {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Text("Download")
                                    }
                                }
                                .disabled(activeDownload != nil || !connection.isConnected)
                            }
                        }
                    }

                    if let activeDownload {
                        ActiveDownloadCard(
                            state: activeDownload,
                            onCancel: cancelActiveDownload
                        )
                    }

                    if let downloadErrorMessage {
                        Text(downloadErrorMessage)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(.red)
                    }
                }

                Section("Installed Models") {
                    if connection.installedModels.isEmpty {
                        Text("No models installed yet.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(connection.installedModels) { model in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.name)
                                        .font(.system(.body, design: .rounded, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text(modelSubtitle(model))
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button(role: .destructive) {
                                    pendingDeleteModel = model
                                } label: {
                                    if deletingModelName == model.name {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Text("Delete")
                                    }
                                }
                                .disabled(deletingModelName != nil || !connection.isConnected)
                            }
                        }
                    }

                    if let deleteErrorMessage {
                        Text(deleteErrorMessage)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refreshData() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .task {
            await refreshData()
        }
        .onDisappear {
            cancelActiveDownload()
        }
        .confirmationDialog(
            "Delete model?",
            isPresented: Binding(
                get: { pendingDeleteModel != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteModel = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let model = pendingDeleteModel {
                Button("Delete \(model.name)", role: .destructive) {
                    Task { await deleteModel(model) }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteModel = nil
            }
        } message: {
            if let model = pendingDeleteModel {
                Text("This removes \(model.name) from Ollama on your Mac.")
            }
        }
    }

    private var statusText: String {
        switch connection.state {
        case .discovering:
            return "Looking for your Mac"
        case .connecting(let peerName):
            return "Connecting to \(peerName)"
        case .reconnecting(let peerName, let attempt):
            return "Reconnecting to \(peerName ?? "your Mac") (Attempt \(attempt))"
        case .connected(let peerName):
            return "Connected to \(peerName)"
        case .failed(let message):
            return message
        }
    }

    private var statusColor: Color {
        switch connection.state {
        case .connected:
            return .green
        case .connecting, .reconnecting:
            return .orange
        case .discovering:
            return .yellow
        case .failed:
            return .red
        }
    }

    private func modelSubtitle(_ model: OllamaModel) -> String {
        let family = model.details?.family?.capitalized ?? "Unknown family"
        guard let parameterSize = model.details?.parameterSize else {
            return family
        }
        return "\(family) • \(parameterSize)"
    }

    private var availableRecommendedModels: [CuratedModel] {
        CuratedModelLibrary.recommended.filter { model in
            !connection.installedModels.contains {
                $0.name == model.id || $0.name.hasPrefix("\(model.id):")
            }
        }
    }

    private func refreshData() async {
        await connection.refreshAvailableHelpers()
        do {
            try await connection.fetchModels()
            deleteErrorMessage = nil
            downloadErrorMessage = nil
        } catch {
            deleteErrorMessage = "Couldn’t refresh models from your Mac."
        }
    }

    private func downloadModel(_ model: CuratedModel) async {
        guard activeDownload == nil else { return }
        guard connection.isConnected else {
            downloadErrorMessage = "Reconnect to your Mac, then try downloading again."
            return
        }

        activeDownload = ModelDownloadState(
            modelID: model.id,
            displayName: model.displayName,
            status: "Starting download…",
            fraction: nil
        )
        downloadErrorMessage = nil

        var didSucceed = false
        do {
            for try await progress in connection.pull(model: model.id) {
                activeDownload = ModelDownloadState(
                    modelID: model.id,
                    displayName: model.displayName,
                    status: progress.status.capitalized,
                    fraction: progress.total == nil ? nil : progress.fraction
                )
                if progress.status == "success" {
                    didSucceed = true
                }
            }
        } catch {
            if error is CancellationError {
                downloadErrorMessage = "Download cancelled."
            } else {
                let localizedMessage =
                    (error as? LocalizedError)?.errorDescription
                    ?? (error as NSError).localizedDescription
                if !localizedMessage.isEmpty {
                    downloadErrorMessage = localizedMessage
                } else {
                    downloadErrorMessage = "Download failed. Please try again."
                }
            }
        }

        activeDownload = nil

        if didSucceed {
            do {
                try await connection.fetchModels()
            } catch {
                downloadErrorMessage = "Model downloaded but refresh failed."
            }
        } else if downloadErrorMessage == nil {
            downloadErrorMessage = "Download didn’t finish. Please try again."
        }
    }

    private func deleteModel(_ model: OllamaModel) async {
        guard connection.isConnected else {
            deleteErrorMessage = "Reconnect to your Mac, then try deleting again."
            return
        }

        deletingModelName = model.name
        pendingDeleteModel = nil
        deleteErrorMessage = nil

        do {
            try await connection.delete(model: model.name)
        } catch {
            deleteErrorMessage = "Couldn’t delete \(model.name). Please try again."
        }

        deletingModelName = nil
    }

    private func startDownload(_ model: CuratedModel) {
        guard downloadTask == nil else { return }
        downloadTask = Task {
            await downloadModel(model)
            await MainActor.run {
                downloadTask = nil
            }
        }
    }

    private func cancelActiveDownload() {
        downloadTask?.cancel()
        downloadTask = nil
    }

    private var diagnosticsEvents: [ConnectionDiagnosticEvent] {
        Array(connection.diagnostics.recentEvents.suffix(14).reversed())
    }

    private func formattedTimestamp(_ date: Date) -> String {
        Self.diagnosticsTimeFormatter.string(from: date)
    }

    private func eventColor(for level: ConnectionDiagnosticLevel) -> Color {
        switch level {
        case .info:
            return .blue
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private func copyDiagnosticsToPasteboard() {
#if os(iOS)
        UIPasteboard.general.string = diagnosticsReportText()
        copiedDiagnostics = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            copiedDiagnostics = false
        }
#endif
    }

    private func diagnosticsReportText() -> String {
        var lines: [String] = []
        let diagnostics = connection.diagnostics
        lines.append("Pasture iOS Connection Diagnostics")
        lines.append("Discovery starts: \(diagnostics.discoveryStarts)")
        lines.append("Peer refreshes: \(diagnostics.peerRefreshes)")
        lines.append("Visible peers: \(diagnostics.visiblePeerCount)")
        lines.append("Visible helpers: \(diagnostics.visibleHelperCount)")
        lines.append("Connect attempts: \(diagnostics.connectAttempts)")
        lines.append("Connect successes: \(diagnostics.connectSuccesses)")
        lines.append("Reconnect schedules: \(diagnostics.reconnectSchedules)")
        lines.append("Reconnect exhausted: \(diagnostics.reconnectExhausted)")
        lines.append("Disconnects: \(diagnostics.disconnects)")
        lines.append("Requests sent: \(diagnostics.requestsSent)")
        lines.append("Responses received: \(diagnostics.responsesReceived)")
        lines.append("Decode failures: \(diagnostics.responseDecodeFailures)")
        lines.append("Request timeouts: \(diagnostics.requestTimeouts)")
        lines.append("Remote errors: \(diagnostics.remoteErrors)")
        lines.append("Chat cancellations: \(diagnostics.chatStreamCancellations)")
        lines.append("Pull cancellations: \(diagnostics.pullStreamCancellations)")

        if let lastError = diagnostics.lastError, !lastError.isEmpty {
            lines.append("Last error: \(lastError)")
        }

        if let loomRuntimeError = diagnostics.loomRuntimeError, !loomRuntimeError.isEmpty {
            lines.append("Loom runtime error: \(loomRuntimeError)")
        }

        if let peerSummary = diagnostics.lastPeerSnapshotSummary, !peerSummary.isEmpty {
            lines.append("Peer snapshot: \(peerSummary)")
        }

        lines.append("Recent events:")
        for event in connection.diagnostics.recentEvents.suffix(30) {
            lines.append("[\(event.level.rawValue.uppercased())] \(formattedTimestamp(event.timestamp)) \(event.message)")
        }
        return lines.joined(separator: "\n")
    }

    private static let diagnosticsTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

struct IntentPickerView: View {
    let palette: EnvironmentPalette
    let reduceTransparency: Bool
    let onSelect: (ChatIntent) -> Void
    @State private var pressedIntent: ChatIntent?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What will you use this for?")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Pick one and Pasture will choose your best model automatically.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(.horizontal, 20)
            .padding(.top, 32)

            VStack(spacing: 10) {
                ForEach(ChatIntent.allCases) { intent in
                    Button {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                            pressedIntent = intent
                        }
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 120_000_000)
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                                pressedIntent = nil
                            }
                            onSelect(intent)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: intent.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(palette.accent)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(intent.title)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)

                                Text(intent.subtitle)
                                    .font(.system(size: 13, weight: .regular, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.68))
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                        .scaleEffect(pressedIntent == intent ? 0.97 : 1)
                    }
                    .buttonStyle(.plain)
                    .modifier(CardSurfaceModifier(reduceTransparency: reduceTransparency, cornerRadius: 22))
                }
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 12)
        }
    }
}

struct LoadingModelsView: View {
    let palette: EnvironmentPalette

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)
            Text("Loading models…")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.76))
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .background(palette.midLayer.opacity(0.34), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.5)
        }
        .padding(.horizontal, 28)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .animation(.easeOut(duration: 0.25), value: palette.layerCount)
    }
}

struct FirstModelSetupView: View {
    let models: [CuratedModel]
    let installedModelNames: Set<String>
    let activeDownload: ModelDownloadState?
    let errorMessage: String?
    let palette: EnvironmentPalette
    let reduceTransparency: Bool
    let isConnected: Bool
    let onDownload: (CuratedModel) async -> Void
    let onRefresh: () async -> Void
    @State private var downloadTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Let’s get your first AI model")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Pick one model to download on your Mac. You can add more any time.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)

            if let activeDownload {
                ActiveDownloadCard(
                    state: activeDownload,
                    onCancel: cancelActiveDownload
                )
                .padding(.horizontal, 16)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
            }

            if !isConnected {
                Text("Pasture is reconnecting to your Mac. Downloads unlock once connection is restored.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.white.opacity(0.84))
                    .padding(.horizontal, 20)
            }

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(models) { model in
                        CuratedModelCard(
                            model: model,
                            palette: palette,
                            reduceTransparency: reduceTransparency,
                            isInstalled: isInstalled(model),
                            isDownloading: activeDownload?.modelID == model.id,
                            isDownloadEnabled: isConnected,
                            onDownload: {
                                startDownload(model)
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            Button {
                Task { await onRefresh() }
            } label: {
                Text("Refresh installed models")
                    .font(.system(.footnote, design: .rounded, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(isConnected ? 0.72 : 0.45))
            .disabled(!isConnected)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .padding(.vertical, 8)
        .onDisappear {
            cancelActiveDownload()
        }
    }

    private func isInstalled(_ model: CuratedModel) -> Bool {
        installedModelNames.contains(model.id)
            || installedModelNames.contains(where: { $0.hasPrefix("\(model.id):") })
    }

    private func startDownload(_ model: CuratedModel) {
        guard downloadTask == nil else { return }
        downloadTask = Task {
            await onDownload(model)
            await MainActor.run {
                downloadTask = nil
            }
        }
    }

    private func cancelActiveDownload() {
        downloadTask?.cancel()
        downloadTask = nil
    }
}

struct ActiveDownloadCard: View {
    let state: ModelDownloadState
    var onCancel: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Downloading \(state.displayName)")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer(minLength: 8)

                if let onCancel {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            Text(state.status)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))

            if let fraction = state.fraction {
                ProgressView(value: fraction)
                    .tint(.white)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .padding(14)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.5)
        }
    }
}

struct CuratedModelCard: View {
    let model: CuratedModel
    let palette: EnvironmentPalette
    let reduceTransparency: Bool
    let isInstalled: Bool
    let isDownloading: Bool
    let isDownloadEnabled: Bool
    let onDownload: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.displayName)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)

                Text(model.description)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))

                HStack(spacing: 6) {
                    ModelTag(text: model.sizeLabel, weight: .semibold)
                    ForEach(model.tags, id: \.self) { tag in
                        ModelTag(text: tag, weight: .medium)
                    }
                }
            }

            Spacer(minLength: 8)

            downloadAction
                .disabled(isInstalled || isDownloading || !isDownloadEnabled)
        }
        .padding(16)
        .modifier(CardSurfaceModifier(reduceTransparency: reduceTransparency, cornerRadius: 24))
    }

    @ViewBuilder
    private var downloadAction: some View {
        if isDownloading {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(palette.userBubble.opacity(0.32), in: Capsule())
        } else if isInstalled {
            Text("Installed")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.white.opacity(0.08), in: Capsule())
        } else {
            Button(action: onDownload) {
                Text("Download")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .modifier(DownloadCapsuleModifier(palette: palette, reduceTransparency: reduceTransparency))
        }
    }
}

struct ModelTag: View {
    let text: String
    let weight: Font.Weight

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: weight, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.08), in: Capsule())
            .foregroundStyle(.white.opacity(0.68))
    }
}

struct ModelPickerChip: View {
    let models: [OllamaModel]
    let selectedModelName: String?
    let palette: EnvironmentPalette
    let reduceTransparency: Bool
    let onSelect: (OllamaModel) -> Void
    @State private var isPressed = false

    var body: some View {
        Menu {
            ForEach(models) { model in
                Button(model.name) {
                    onSelect(model)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedModelName ?? "Select model")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .scaleEffect(isPressed ? 0.96 : 1)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isPressed = true
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 160_000_000)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isPressed = false
                }
            }
        })
        .modifier(ModelChipSurfaceModifier(palette: palette, reduceTransparency: reduceTransparency))
    }
}

// MARK: - Message bubble

struct MessageBubble: View {
    let message: Message
    let userBubbleColor: Color

    var body: some View {
        HStack {
            if message.role == "user" { Spacer() }

            bubbleContent
                .frame(maxWidth: 312, alignment: message.role == "user" ? .trailing : .leading)

            if message.role != "user" { Spacer() }
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if message.role == "user" {
            Text(message.content)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .background(userBubbleColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .foregroundStyle(.white)
        } else {
            Markdown(message.content)
                .markdownTheme(.basic)
                .markdownTextStyle {
                    ForegroundColor(.black.opacity(0.82))
                    BackgroundColor(nil)
                }
                .markdownTextStyle(\.link) {
                    ForegroundColor(.blue.opacity(0.9))
                }
                .textSelection(.enabled)
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 0.5)
                }
        }
    }
}

struct StreamingBubble: View {
    let text: String
    @State private var cursorVisible = false

    var body: some View {
        HStack {
            ZStack(alignment: .bottomTrailing) {
                Markdown(text.isEmpty ? " " : text)
                    .markdownTheme(.basic)
                    .markdownTextStyle {
                        ForegroundColor(.black.opacity(0.82))
                        BackgroundColor(nil)
                    }
                    .markdownTextStyle(\.link) {
                        ForegroundColor(.blue.opacity(0.9))
                    }
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("▍")
                    .opacity(cursorVisible ? 1 : 0.35)
                    .foregroundStyle(Color.black.opacity(0.66))
                    .padding(.trailing, 2)
                    .padding(.bottom, 1)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 0.5)
            }
            .frame(maxWidth: 312, alignment: .leading)
            Spacer()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                cursorVisible = true
            }
        }
    }
}

// MARK: - Compose bar

struct ComposeBar: View {
    let palette: EnvironmentPalette
    let reduceTransparency: Bool
    let isDisabled: Bool
    let onSend: (String) async -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            TextField(
                "",
                text: $text,
                prompt: Text("Ask something").foregroundStyle(.white.opacity(0.62)),
                axis: .vertical
            )
            .font(.system(size: 16, weight: .regular, design: .rounded))
            .foregroundStyle(.white)
            .focused($focused)
            .lineLimit(1...5)
            .disabled(isDisabled)

            sendButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .modifier(ComposeBarSurfaceModifier(palette: palette, reduceTransparency: reduceTransparency))
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focused = false
                }
                .font(.system(.body, design: .rounded, weight: .semibold))
            }
        }
    }

    @ViewBuilder
    private var sendButton: some View {
        Button {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            text = ""
            Task { await onSend(trimmed) }
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(canSend ? .white : .white.opacity(0.3))
                .frame(width: 34, height: 34)
                .background {
                    buttonBackground
                }
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: canSend)
    }

    @ViewBuilder
    private var buttonBackground: some View {
        if canSend, #available(iOS 26.0, *), !reduceTransparency {
            Circle()
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: Circle())
        } else {
            Circle().fill(canSend ? palette.userBubble : .white.opacity(0.2))
        }
    }

    private var canSend: Bool {
        !isDisabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct TopBarCircleButton: View {
    let systemName: String
    let palette: EnvironmentPalette
    let reduceTransparency: Bool
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 34, height: 34)
                .modifier(TopBarButtonSurfaceModifier(palette: palette, reduceTransparency: reduceTransparency, isEnabled: isEnabled))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct ChatConnectionRecoveryBanner: View {
    let state: ConnectionManager.ConnectionState
    let palette: EnvironmentPalette
    let reduceTransparency: Bool
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if showsRetry {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.accent)
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.white)
            }

            Text(message)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(2)

            Spacer(minLength: 8)

            if showsRetry {
                Button("Retry", action: onRetry)
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .modifier(RecoveryBannerSurfaceModifier(palette: palette, reduceTransparency: reduceTransparency))
    }

    private var showsRetry: Bool {
        if case .failed = state {
            return true
        }
        return false
    }

    private var message: String {
        switch state {
        case .discovering:
            return "Looking for your Mac…"
        case .connecting(let peerName):
            return "Connecting to \(peerName)…"
        case .reconnecting(let peerName, let attempt):
            return "Reconnecting to \(peerName ?? "your Mac") (Attempt \(attempt))…"
        case .failed(let message):
            return message
        case .connected:
            return ""
        }
    }
}

private struct CardSurfaceModifier: ViewModifier {
    let reduceTransparency: Bool
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: max(18, cornerRadius - 6), style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: max(18, cornerRadius - 6), style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 0.5)
                }
        }
    }
}

private struct DownloadCapsuleModifier: ViewModifier {
    let palette: EnvironmentPalette
    let reduceTransparency: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular.tint(palette.userBubble.opacity(0.34)).interactive(), in: Capsule())
        } else {
            content.background(palette.userBubble, in: Capsule())
        }
    }
}

private struct ModelChipSurfaceModifier: ViewModifier {
    let palette: EnvironmentPalette
    let reduceTransparency: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular.tint(palette.accent.opacity(0.26)), in: Capsule())
        } else {
            content
                .background(palette.accent.opacity(0.14), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(palette.accent.opacity(0.22), lineWidth: 0.5)
                }
        }
    }
}

private struct TopBarButtonSurfaceModifier: ViewModifier {
    let palette: EnvironmentPalette
    let reduceTransparency: Bool
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency, isEnabled {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content.background(.white.opacity(0.10), in: Circle())
        }
    }
}

private struct RecoveryBannerSurfaceModifier: ViewModifier {
    let palette: EnvironmentPalette
    let reduceTransparency: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(palette.nearLayer.opacity(0.44), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.10), lineWidth: 0.5)
                }
        }
    }
}

private struct ComposeBarSurfaceModifier: ViewModifier {
    let palette: EnvironmentPalette
    let reduceTransparency: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        } else {
            content
                .background(palette.nearLayer.opacity(0.64), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(.white.opacity(0.12))
                        .frame(height: 0.5)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
        }
    }
}
