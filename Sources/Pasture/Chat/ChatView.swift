import SwiftUI
import MarkdownUI
import SwiftData
#if os(iOS)
import UIKit
#endif

struct ChatView: View {
    @EnvironmentObject var connection: ConnectionManager
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = ChatViewModel()
    @State private var isShowingSettings = false
    @State private var isShowingNewChatConfirmation = false

    var body: some View {
        ZStack {
            EnvironmentBackground(environment: currentEnvironment)
                .id(currentEnvironment.id)
                .transition(.opacity)

            if viewModel.isLoadingModels {
                LoadingModelsView()
            } else if viewModel.needsModelSetup {
                FirstModelSetupView(
                    models: CuratedModelLibrary.recommended,
                    installedModelNames: viewModel.installedModelNames,
                    activeDownload: viewModel.activeDownload,
                    errorMessage: viewModel.modelLoadError,
                    isConnected: connection.isConnected,
                    onDownload: { model in
                        await viewModel.download(curatedModel: model, connection: connection)
                    },
                    onRefresh: {
                        await viewModel.loadModels(connection: connection)
                    }
                )
            } else if viewModel.shouldShowIntentPicker {
                IntentPickerView { intent in
                    viewModel.chooseIntent(intent)
                }
            } else {
                chatContent
            }
        }
        .task {
            viewModel.bootstrapPersistence(modelContext: modelContext)
            await viewModel.loadModels(connection: connection)
        }
        .onChange(of: connection.installedModels) { _, newModels in
            viewModel.applyInstalledModels(newModels)
        }
        .animation(.easeInOut(duration: 0.6), value: currentEnvironment.id)
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

    private var currentEnvironment: ModelEnvironment {
        ModelEnvironment.forModelName(viewModel.selectedModel?.name)
    }

    private var chatContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if !viewModel.installedModels.isEmpty {
                    ModelPickerChip(
                        models: viewModel.installedModels,
                        selectedModelName: viewModel.selectedModel?.name
                    ) { selected in
                        viewModel.selectModel(selected, userInitiated: true)
                    }
                }

                Spacer()

                Button {
                    if viewModel.hasMessages {
                        isShowingNewChatConfirmation = true
                    } else {
                        viewModel.startNewChat()
                    }
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(9)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isStreaming)

                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(9)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)
            .padding(.horizontal, 16)

            if !connection.isConnected {
                HStack(spacing: 10) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.orange)

                    Text(connectionStatusBannerText)
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Button("Retry") {
                        Task { await connection.startDiscovery() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .padding(.top, 8)
                .padding(.horizontal, 16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            if let modelLoadError = viewModel.modelLoadError {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 12, weight: .semibold))
                    Text(modelLoadError)
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
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
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            Spacer()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(
                                message: message,
                                userBubbleColor: currentEnvironment.palette.userBubble
                            )
                                .id(message.id)
                        }
                        if viewModel.isStreaming {
                            StreamingBubble(text: viewModel.streamingText)
                                .id("streaming")
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.streamingText) { _, _ in
                    withAnimation { proxy.scrollTo("streaming") }
                }
            }

            ComposeBar(
                isDisabled: viewModel.isStreaming || viewModel.selectedModel == nil || !connection.isConnected
            ) { text in
                await viewModel.send(text: text, connection: connection)
            }
        }
    }

    private var connectionStatusBannerText: String {
        switch connection.state {
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
    let onSelect: (ChatIntent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What will you use this for?")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Pick one and Pasture will choose your best model automatically.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)

            VStack(spacing: 12) {
                ForEach(ChatIntent.allCases) { intent in
                    Button {
                        onSelect(intent)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: intent.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 26)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(intent.title)
                                    .font(.system(.headline, design: .rounded))
                                    .foregroundStyle(.primary)

                                Text(intent.subtitle)
                                    .font(.system(.footnote, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 12)
        }
    }
}

struct LoadingModelsView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white)
            Text("Loading models from your Mac…")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 24)
    }
}

struct FirstModelSetupView: View {
    let models: [CuratedModel]
    let installedModelNames: Set<String>
    let activeDownload: ModelDownloadState?
    let errorMessage: String?
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
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

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
                    .padding(.horizontal, 16)
            }

            if !isConnected {
                Text("Pasture is reconnecting to your Mac. Downloads will unlock as soon as the connection is back.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 16)
            }

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(models) { model in
                        CuratedModelCard(
                            model: model,
                            isInstalled: isInstalled(model),
                            isDownloading: activeDownload?.modelID == model.id,
                            isDownloadEnabled: isConnected,
                            onDownload: {
                                startDownload(model)
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            Button {
                Task { await onRefresh() }
            } label: {
                Text("Refresh installed models")
                    .font(.system(.footnote, design: .rounded, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(isConnected ? 0.85 : 0.55))
            .disabled(!isConnected)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
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

                Spacer(minLength: 8)

                if let onCancel {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            Text(state.status)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.secondary)

            if let fraction = state.fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView()
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct CuratedModelCard: View {
    let model: CuratedModel
    let isInstalled: Bool
    let isDownloading: Bool
    let isDownloadEnabled: Bool
    let onDownload: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.displayName)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.primary)

                Text(model.description)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ModelTag(text: model.sizeLabel)
                    ForEach(model.tags, id: \.self) { tag in
                        ModelTag(text: tag)
                    }
                }
            }

            Spacer(minLength: 8)

            Button {
                onDownload()
            } label: {
                Text(buttonTitle)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(buttonBackground, in: Capsule())
            }
            .disabled(isInstalled || isDownloading || !isDownloadEnabled)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var buttonTitle: String {
        if isInstalled { return "Installed" }
        if isDownloading { return "Downloading" }
        return "Download"
    }

    private var buttonBackground: Color {
        if isInstalled { return .green.opacity(0.25) }
        if isDownloading { return .orange.opacity(0.2) }
        return .blue.opacity(0.18)
    }
}

struct ModelTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.18), in: Capsule())
            .foregroundStyle(.primary)
    }
}

struct ModelPickerChip: View {
    let models: [OllamaModel]
    let selectedModelName: String?
    let onSelect: (OllamaModel) -> Void

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
                    .font(.system(.caption, design: .rounded, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .menuStyle(.button)
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
                .frame(maxWidth: 280, alignment: message.role == "user" ? .trailing : .leading)

            if message.role != "user" { Spacer() }
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if message.role == "user" {
            Text(message.content)
                .font(.system(.body, design: .rounded))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(userBubbleColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            Markdown(message.content)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

struct StreamingBubble: View {
    let text: String

    var body: some View {
        HStack {
            Text(text.isEmpty ? "▍" : text)
                .font(.system(.body, design: .rounded))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(maxWidth: 280, alignment: .leading)
            Spacer()
        }
    }
}

// MARK: - Compose bar

struct ComposeBar: View {
    let isDisabled: Bool
    let onSend: (String) async -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            TextField("Message", text: $text, axis: .vertical)
                .font(.system(.body, design: .rounded))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .focused($focused)
                .lineLimit(1...5)
                .disabled(isDisabled)

            Button {
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                let message = text
                text = ""
                Task { await onSend(message) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(isDisabled || text.isEmpty ? .white.opacity(0.4) : .white)
            }
            .disabled(isDisabled || text.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}
