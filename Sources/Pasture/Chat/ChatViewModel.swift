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

    var needsModelSetup: Bool {
        !isLoadingModels && modelLoadError == nil && installedModels.isEmpty
    }

    var installedModelNames: Set<String> {
        Set(installedModels.map(\.name))
    }

    var hasMessages: Bool { !messages.isEmpty }

    private let conversation: ConversationRecord
    private let modelContext: ModelContext

    private enum DefaultsKeys {
        static let selectedModelName = "pasture.chat.selectedModelName"
        static let cachedModels = "pasture.chat.cachedModels"
    }

    init(conversation: ConversationRecord, modelContext: ModelContext) {
        self.conversation = conversation
        self.modelContext = modelContext

        restoreCachedModels()

        // Load messages already saved to this conversation
        let sorted = conversation.messages.sorted { $0.createdAt < $1.createdAt }
        messages = sorted.map { Message(role: $0.role, content: $0.content) }

        // Restore model: prefer conversation's saved model, then last globally selected, then first
        let preferredName = conversation.modelName
            ?? UserDefaults.standard.string(forKey: DefaultsKeys.selectedModelName)
        if let name = preferredName,
           let match = installedModels.first(where: { $0.name == name }) {
            selectedModel = match
        } else {
            selectedModel = installedModels.first
        }
    }

    // MARK: - Model management

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
            modelLoadError = "Couldn't load models from your Mac. Please try again."
        }

        isLoadingModels = false
    }

    func applyInstalledModels(_ models: [OllamaModel]) {
        installedModels = models

        if let current = selectedModel,
           installedModels.contains(where: { $0.name == current.name }) {
            cacheInstalledModels()
            updateConversationMeta()
            return
        }

        let preferredName = conversation.modelName
            ?? UserDefaults.standard.string(forKey: DefaultsKeys.selectedModelName)
        if let name = preferredName,
           let match = installedModels.first(where: { $0.name == name }) {
            selectedModel = match
        } else {
            selectedModel = installedModels.first
        }

        cacheInstalledModels()
        updateConversationMeta()
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
        updateConversationMeta()
    }

    func isInstalled(_ curatedModel: CuratedModel) -> Bool {
        installedModels.contains {
            $0.name == curatedModel.id || $0.name.hasPrefix("\(curatedModel.id):")
        }
    }

    func download(curatedModel: CuratedModel, connection: ConnectionManager) async {
        guard activeDownload == nil, !isInstalled(curatedModel) else { return }

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
                if progress.status == "success" { didSucceed = true }
            }
        } catch {
            modelLoadError = error is CancellationError
                ? "Download cancelled."
                : userFacingError(for: error, fallback: "Model download failed. Please try again.")
        }

        if didSucceed {
            await loadModels(connection: connection)
            if let downloaded = installedModels.first(where: {
                $0.name == curatedModel.id || $0.name.hasPrefix("\(curatedModel.id):")
            }) {
                selectModel(downloaded)
            }
        } else if modelLoadError == nil {
            modelLoadError = "Model download didn't finish. Please try again."
        }

        activeDownload = nil
    }

    // MARK: - Sending

    func send(text: String, connection: ConnectionManager) async {
        guard let model = selectedModel else { return }

        guard connection.isConnected else {
            let msg = "Connection to your Mac is currently unavailable. Pasture is reconnecting in the background."
            appendAndPersist(role: "assistant", content: msg)
            return
        }

#if os(iOS)
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
#endif

        appendAndPersist(role: "user", content: text)
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

        streamingText = ""
        isStreaming = false

        if !fullResponse.isEmpty {
            appendAndPersist(role: "assistant", content: fullResponse)
            if let err = streamErrorMessage {
                appendAndPersist(role: "assistant", content: "Response interrupted: \(err)")
            }
        } else if let err = streamErrorMessage {
            appendAndPersist(role: "assistant", content: err)
        } else if !connection.isConnected {
            appendAndPersist(
                role: "assistant",
                content: "The response was interrupted because your Mac disconnected. Please try again in a moment."
            )
        }
    }

    // MARK: - Persistence

    private func appendAndPersist(role: String, content: String) {
        messages.append(Message(role: role, content: content))
        let record = MessageRecord(role: role, content: content, conversation: conversation)
        modelContext.insert(record)
        conversation.updatedAt = .now
        conversation.modelName = selectedModel?.name

        if conversation.title == nil, role == "user" {
            conversation.title = autoTitle(from: content)
        }

        try? modelContext.save()
    }

    private func updateConversationMeta() {
        conversation.modelName = selectedModel?.name
        try? modelContext.save()
    }

    private func autoTitle(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        guard firstLine.count > 45 else { return firstLine }
        return String(firstLine.prefix(42)) + "…"
    }

    private func cacheInstalledModels() {
        guard let encoded = try? JSONEncoder().encode(installedModels) else { return }
        UserDefaults.standard.set(encoded, forKey: DefaultsKeys.cachedModels)
    }

    private func restoreCachedModels() {
        guard let encoded = UserDefaults.standard.data(forKey: DefaultsKeys.cachedModels),
              let decoded = try? JSONDecoder().decode([OllamaModel].self, from: encoded)
        else { return }
        installedModels = decoded.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func userFacingError(for error: Error, fallback: String) -> String {
        if error is CancellationError { return "Request cancelled." }
        if let proxyError = error as? ProxyError,
           let message = proxyError.errorDescription, !message.isEmpty {
            return message
        }
        let msg = (error as NSError).localizedDescription
        if !msg.isEmpty, msg != "(null)" { return msg }
        return fallback
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
