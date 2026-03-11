import Foundation
import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var messages: [Message] = []
    @Published private(set) var isStreaming = false
    @Published private(set) var streamingText = ""
    @Published private(set) var selectedModel: OllamaModel?
    @Published private(set) var installedModels: [OllamaModel] = []
    @Published private(set) var isLoadingModels = false
    @Published private(set) var modelLoadError: String?
    @Published private(set) var activeDownload: ModelDownloadState?
    @Published private(set) var selectedIntent: ChatIntent?
    @Published private(set) var hasCompletedIntentSelection = false

    var needsModelSetup: Bool {
        !isLoadingModels && modelLoadError == nil && installedModels.isEmpty
    }

    var installedModelNames: Set<String> {
        Set(installedModels.map(\.name))
    }

    var shouldShowIntentPicker: Bool {
        !isLoadingModels && modelLoadError == nil && !installedModels.isEmpty && !hasCompletedIntentSelection
    }

    var hasMessages: Bool {
        !messages.isEmpty
    }

    private enum DefaultsKeys {
        static let selectedIntent = "pasture.chat.intent"
        static let selectedModelName = "pasture.chat.selectedModelName"
        static let hasCompletedIntent = "pasture.chat.hasCompletedIntent"
        static let cachedModels = "pasture.chat.cachedModels"
    }

    private var modelContext: ModelContext?
    private var historyRecord: ConversationHistoryRecord?
    private var hasBootstrappedPersistence = false

    init() {
        let defaults = UserDefaults.standard
        if let intentRawValue = defaults.string(forKey: DefaultsKeys.selectedIntent),
           let intent = ChatIntent(rawValue: intentRawValue) {
            selectedIntent = intent
        }
        hasCompletedIntentSelection = defaults.bool(forKey: DefaultsKeys.hasCompletedIntent)
        restoreCachedModels()
    }

    func bootstrapPersistence(modelContext: ModelContext) {
        guard !hasBootstrappedPersistence else { return }
        hasBootstrappedPersistence = true
        self.modelContext = modelContext

        var descriptor = FetchDescriptor<ConversationHistoryRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        do {
            guard let existingRecord = try modelContext.fetch(descriptor).first else { return }
            historyRecord = existingRecord

            if !existingRecord.payload.isEmpty,
               let restoredMessages = try? JSONDecoder().decode(
                    [PersistedConversationMessage].self,
                    from: existingRecord.payload
               ) {
                messages = restoredMessages.map { Message(role: $0.role, content: $0.content) }
            }

            let defaults = UserDefaults.standard
            if defaults.string(forKey: DefaultsKeys.selectedModelName) == nil,
               let selectedModelName = existingRecord.selectedModelName {
                defaults.set(selectedModelName, forKey: DefaultsKeys.selectedModelName)
            }

            if defaults.string(forKey: DefaultsKeys.selectedIntent) == nil,
               let selectedIntentRawValue = existingRecord.selectedIntentRawValue {
                defaults.set(selectedIntentRawValue, forKey: DefaultsKeys.selectedIntent)
                defaults.set(true, forKey: DefaultsKeys.hasCompletedIntent)
                if let restoredIntent = ChatIntent(rawValue: selectedIntentRawValue) {
                    selectedIntent = restoredIntent
                    hasCompletedIntentSelection = true
                }
            }
        } catch {
            print("[ChatViewModel] Failed to load conversation history: \(error)")
        }
    }

    func loadModels(connection: ConnectionManager) async {
        isLoadingModels = true
        modelLoadError = nil

        do {
            try await connection.fetchModels()
            applyInstalledModels(
                connection.installedModels.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            )
        } catch {
            print("[ChatViewModel] Failed to fetch models: \(error)")
            modelLoadError = "Couldn’t load models from your Mac. Please try again."
        }

        isLoadingModels = false
    }

    func applyInstalledModels(_ models: [OllamaModel]) {
        installedModels = models

        let defaults = UserDefaults.standard
        let savedModelName = defaults.string(forKey: DefaultsKeys.selectedModelName)

        if let selectedModel,
           installedModels.contains(where: { $0.name == selectedModel.name }) {
            cacheInstalledModels()
            persistConversation()
            return
        }

        if let savedModelName,
           let savedModel = installedModels.first(where: { $0.name == savedModelName }) {
            selectedModel = savedModel
            cacheInstalledModels()
            persistConversation()
            return
        }

        selectedModel = installedModels.first
        cacheInstalledModels()
        persistConversation()
    }

    func selectModel(_ model: OllamaModel, userInitiated: Bool = false) {
        guard selectedModel?.name != model.name else { return }
        selectedModel = model
        UserDefaults.standard.set(model.name, forKey: DefaultsKeys.selectedModelName)
        cacheInstalledModels()

#if os(iOS)
        if userInitiated {
            let feedback = UIImpactFeedbackGenerator(style: .medium)
            feedback.impactOccurred()
        }
#endif
        persistConversation()
    }

    func isInstalled(_ curatedModel: CuratedModel) -> Bool {
        installedModels.contains {
            $0.name == curatedModel.id || $0.name.hasPrefix("\(curatedModel.id):")
        }
    }

    func chooseIntent(_ intent: ChatIntent) {
        selectedIntent = intent
        hasCompletedIntentSelection = true

        let defaults = UserDefaults.standard
        defaults.set(intent.rawValue, forKey: DefaultsKeys.selectedIntent)
        defaults.set(true, forKey: DefaultsKeys.hasCompletedIntent)

        if let recommended = recommendModel(for: intent) {
            selectModel(recommended)
        }

        persistConversation()
    }

    func download(curatedModel: CuratedModel, connection: ConnectionManager) async {
        guard activeDownload == nil else { return }
        guard !isInstalled(curatedModel) else { return }

        activeDownload = ModelDownloadState(
            modelID: curatedModel.id,
            displayName: curatedModel.displayName,
            status: "Starting download…",
            fraction: nil
        )
        modelLoadError = nil

        var didSucceed = false
        do {
            for try await progress in connection.pull(model: curatedModel.id) {
                activeDownload = ModelDownloadState(
                    modelID: curatedModel.id,
                    displayName: curatedModel.displayName,
                    status: progress.status.capitalized,
                    fraction: progress.total == nil ? nil : progress.fraction
                )

                if progress.status == "success" {
                    didSucceed = true
                }
            }
        } catch {
            if error is CancellationError {
                modelLoadError = "Download cancelled."
            } else {
            modelLoadError = userFacingError(
                for: error,
                fallback: "Model download failed. Please try again."
            )
            }
        }

        if didSucceed {
            await loadModels(connection: connection)
            if let downloadedModel = installedModels.first(where: {
                $0.name == curatedModel.id || $0.name.hasPrefix("\(curatedModel.id):")
            }) {
                selectModel(downloadedModel)
            }
        } else if modelLoadError == nil {
            modelLoadError = "Model download didn’t finish. Please try again."
        }

        activeDownload = nil
    }

    func send(text: String, connection: ConnectionManager) async {
        guard let model = selectedModel else { return }
        guard connection.isConnected else {
            messages.append(
                Message(
                    role: "assistant",
                    content: "Connection to your Mac is currently unavailable. Pasture is reconnecting in the background."
                )
            )
            persistConversation()
            return
        }

#if os(iOS)
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
#endif

        let userMessage = Message(role: "user", content: text)
        messages.append(userMessage)
        persistConversation()

        let history = messages.map { ChatMessage(role: $0.role, content: $0.content) }

        isStreaming = true
        streamingText = ""

        var fullResponse = ""
        var streamErrorMessage: String?

        do {
            for try await token in connection.chat(model: model.name, messages: history) {
                fullResponse += token
                streamingText = fullResponse
            }
        } catch {
            streamErrorMessage = userFacingError(
                for: error,
                fallback: "The response was interrupted before completion."
            )
        }

        if !fullResponse.isEmpty {
            messages.append(Message(role: "assistant", content: fullResponse))
            persistConversation()
        } else if let streamErrorMessage {
            messages.append(
                Message(
                    role: "assistant",
                    content: streamErrorMessage
                )
            )
            persistConversation()
        } else if !connection.isConnected {
            messages.append(
                Message(
                    role: "assistant",
                    content: "The response was interrupted because your Mac disconnected. Please try again in a moment."
                )
            )
            persistConversation()
        }

        if !fullResponse.isEmpty, let streamErrorMessage {
            messages.append(
                Message(
                    role: "assistant",
                    content: "Response interrupted: \(streamErrorMessage)"
                )
            )
            persistConversation()
        }

        streamingText = ""
        isStreaming = false
    }

    func startNewChat() {
        messages.removeAll()
        streamingText = ""
        isStreaming = false
        persistConversation()
    }

    private func persistConversation() {
        guard let modelContext else { return }

        let payload: Data
        do {
            payload = try JSONEncoder().encode(
                messages.map { PersistedConversationMessage(role: $0.role, content: $0.content) }
            )
        } catch {
            print("[ChatViewModel] Failed to encode conversation history: \(error)")
            return
        }

        let now = Date()
        let activeRecord: ConversationHistoryRecord
        if let historyRecord {
            activeRecord = historyRecord
        } else {
            let created = ConversationHistoryRecord(
                createdAt: now,
                updatedAt: now,
                selectedModelName: selectedModel?.name,
                selectedIntentRawValue: selectedIntent?.rawValue,
                payload: payload
            )
            modelContext.insert(created)
            historyRecord = created
            activeRecord = created
        }

        activeRecord.updatedAt = now
        activeRecord.selectedModelName = selectedModel?.name
        activeRecord.selectedIntentRawValue = selectedIntent?.rawValue
        activeRecord.payload = payload

        do {
            try modelContext.save()
        } catch {
            print("[ChatViewModel] Failed to persist conversation history: \(error)")
        }
    }

    private func cacheInstalledModels() {
        guard let encoded = try? JSONEncoder().encode(installedModels) else { return }
        UserDefaults.standard.set(encoded, forKey: DefaultsKeys.cachedModels)
    }

    private func restoreCachedModels() {
        let defaults = UserDefaults.standard
        guard let encoded = defaults.data(forKey: DefaultsKeys.cachedModels),
              let decoded = try? JSONDecoder().decode([OllamaModel].self, from: encoded)
        else {
            return
        }

        installedModels = decoded.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        if let savedModelName = defaults.string(forKey: DefaultsKeys.selectedModelName),
           let savedModel = installedModels.first(where: { $0.name == savedModelName }) {
            selectedModel = savedModel
        } else {
            selectedModel = installedModels.first
        }
    }

    private func userFacingError(for error: Error, fallback: String) -> String {
        if error is CancellationError {
            return "Request cancelled."
        }

        if let proxyError = error as? ProxyError,
           let message = proxyError.errorDescription,
           !message.isEmpty {
            return message
        }

        let localizedMessage = (error as NSError).localizedDescription
        if !localizedMessage.isEmpty, localizedMessage != "(null)" {
            return localizedMessage
        }

        return fallback
    }

    private func recommendModel(for intent: ChatIntent) -> OllamaModel? {
        installedModels.max { lhs, rhs in
            score(lhs, for: intent) < score(rhs, for: intent)
        }
    }

    private func score(_ model: OllamaModel, for intent: ChatIntent) -> Int {
        let name = model.name.lowercased()

        switch intent {
        case .coding:
            if name.contains("coder") || name.contains("code") || name.contains("codellama") { return 100 }
            if name.contains("qwen") || name.contains("deepseek") { return 80 }
            if name.contains("llama") || name.contains("mistral") { return 60 }
            return 30

        case .writing:
            if name.contains("mistral") || name.contains("llama") { return 100 }
            if name.contains("qwen") || name.contains("gemma") { return 80 }
            if name.contains("phi") { return 60 }
            return 30

        case .research:
            if name.contains("deepseek") || name.contains("r1") { return 100 }
            if name.contains("qwen") || name.contains("mistral") { return 85 }
            if name.contains("llama") { return 70 }
            return 30

        case .chat:
            if name.contains("3b") || name.contains("mini") || name.contains("2b") { return 100 }
            if name.contains("llama") || name.contains("gemma") || name.contains("phi") { return 80 }
            if name.contains("qwen") || name.contains("mistral") { return 70 }
            return 30
        }
    }
}

struct Message: Identifiable {
    let id = UUID()
    let role: String
    let content: String
}

struct ModelDownloadState: Equatable {
    let modelID: String
    let displayName: String
    let status: String
    let fraction: Double?
}
