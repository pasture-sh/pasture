import Foundation
import SwiftUI
import SwiftData
import os.log
import PastureShared
#if os(iOS)
import UIKit
#endif

private let log = Logger(subsystem: "com.amrith.pasture", category: "ChatViewModel")

@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var messages: [Message] = []
    @Published private(set) var isStreaming = false
    @Published private(set) var streamingText = ""
    @Published private(set) var connectionError: String?
    @Published private(set) var selectedModel: OllamaModel?
    @Published private(set) var installedModels: [OllamaModel] = []
    @Published private(set) var isLoadingModels = false
    @Published private(set) var modelLoadError: String?
    @Published private(set) var activeDownload: ModelDownloadState?
    @Published private(set) var failedMessageID: Message.ID?
    @Published var replyMessage: Message? = nil

    private var streamingTask: Task<Void, Never>?

    func clearConnectionError() {
        connectionError = nil
    }

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
        static let systemPrompts = "pasture.chat.systemPrompts"
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
            // Current selection is still valid; no need to re-resolve.
        } else {
            let preferredName = conversation.modelName
                ?? UserDefaults.standard.string(forKey: DefaultsKeys.selectedModelName)
            if let name = preferredName,
               let match = installedModels.first(where: { $0.name == name }) {
                selectedModel = match
            } else {
                selectedModel = installedModels.first
            }
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
        installedModels.contains { $0.matches(curatedModel) }
    }

    func download(curatedModel: CuratedModel, connection: ConnectionManager) async {
        guard activeDownload == nil, !isInstalled(curatedModel) else { return }

        var state = ModelDownloadState(
            modelID: curatedModel.id,
            displayName: curatedModel.displayName,
            status: "Starting download…",
            fraction: nil
        )
        activeDownload = state
        modelLoadError = nil

        var didSucceed = false
        do {
            for try await progress in connection.pull(model: curatedModel.id) {
                state = state.updating(with: progress)
                activeDownload = state
                if progress.isComplete { didSucceed = true }
            }
        } catch {
            modelLoadError = error is CancellationError
                ? "Download cancelled."
                : userFacingError(for: error, fallback: "Model download failed. Please try again.")
        }

        if didSucceed {
            await loadModels(connection: connection)
            if let downloaded = installedModels.first(where: { $0.matches(curatedModel) }) {
                selectModel(downloaded)
            }
        } else if modelLoadError == nil {
            modelLoadError = "Model download didn't finish. Please try again."
        }

        activeDownload = nil
    }

    // MARK: - System prompts

    func systemPrompt(for modelName: String) -> String {
        let dict = UserDefaults.standard.dictionary(forKey: DefaultsKeys.systemPrompts) as? [String: String]
        return dict?[modelName] ?? ""
    }

    func setSystemPrompt(_ prompt: String, for modelName: String) {
        var dict = (UserDefaults.standard.dictionary(forKey: DefaultsKeys.systemPrompts) as? [String: String]) ?? [:]
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { dict.removeValue(forKey: modelName) } else { dict[modelName] = trimmed }
        UserDefaults.standard.set(dict, forKey: DefaultsKeys.systemPrompts)
    }

    // MARK: - Sending

    func send(text: String, connection: ConnectionManager) async {
        guard let model = selectedModel else { return }

        guard connection.isConnected else {
            connectionError = "Reconnecting to your Mac — please try again in a moment."
            return
        }
        connectionError = nil
        failedMessageID = nil

#if os(iOS)
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
#endif

        let fullText: String
        if let reply = replyMessage {
            let who = reply.role == MessageRole.user.rawValue ? "You previously said" : "The AI previously said"
            fullText = "> \(who): \"\(reply.content.prefix(200))\"\n\n\(text)"
        } else {
            fullText = text
        }
        replyMessage = nil

        appendAndPersist(role: .user, content: fullText)
        let lastUserMessageID = messages.last(where: { $0.role == MessageRole.user.rawValue })?.id

        await runStream(model: model, connection: connection, lastUserMessageID: lastUserMessageID)
    }

    func retryFailed(connection: ConnectionManager) async {
        guard failedMessageID != nil, let model = selectedModel else { return }
        failedMessageID = nil
        connectionError = nil

#if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif

        await runStream(model: model, connection: connection, lastUserMessageID: nil)
    }

    func cancelStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
    }

    private func runStream(
        model: OllamaModel,
        connection: ConnectionManager,
        lastUserMessageID: Message.ID?
    ) async {
        var history = messages.map { ChatMessage(role: $0.role, content: $0.content) }
        let promptText = systemPrompt(for: model.name)
        if !promptText.isEmpty {
            history.insert(ChatMessage(role: "system", content: promptText), at: 0)
        }

        isStreaming = true
        streamingText = ""

        var fullResponse = ""
        var streamErrorMessage: String?

        let task = Task {
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
        }
        streamingTask = task
        await task.value
        streamingTask = nil

        streamingText = ""
        isStreaming = false

        if !fullResponse.isEmpty {
            appendAndPersist(role: .assistant, content: fullResponse)
#if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
#endif
            let markdown = conversationMarkdown()
            let filename = conversationFilename()
            Task { @MainActor in
                await connection.backup(filename: "Conversations/\(filename)", payload: markdown)
            }
            if let err = streamErrorMessage {
                connectionError = err
            }
        } else if let err = streamErrorMessage {
            connectionError = err
            failedMessageID = lastUserMessageID
        } else if !connection.isConnected {
            connectionError = "Reconnecting to your Mac — please try again in a moment."
            failedMessageID = lastUserMessageID
        }
    }

    // MARK: - Backup

    func conversationFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: conversation.createdAt)
        let title = (conversation.title ?? "Conversation")
            .components(separatedBy: .init(charactersIn: "/:*?\"<>|\\"))
            .joined(separator: "-")
        return "\(date) - \(title).md"
    }

    func conversationMarkdown() -> String {
        let title = conversation.title ?? "Conversation"
        let modelName = conversation.modelName ?? "Unknown model"
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let dateStr = formatter.string(from: conversation.createdAt)

        var lines: [String] = [
            "# \(title)",
            "",
            "**Model:** \(modelName)",
            "**Started:** \(dateStr)",
            "",
            "---",
            ""
        ]

        for message in messages {
            let label = message.role == MessageRole.user.rawValue ? "You" : "Pasture"
            lines.append("**\(label):** \(message.content)")
            lines.append("")
            lines.append("---")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Persistence

    private func appendAndPersist(role: MessageRole, content: String) {
        messages.append(Message(role: role.rawValue, content: content))
        let record = MessageRecord(role: role.rawValue, content: content, conversation: conversation)
        modelContext.insert(record)
        conversation.updatedAt = .now
        conversation.modelName = selectedModel?.name

        if conversation.title == nil, role == .user {
            conversation.title = autoTitle(from: content)
        }

        do {
            try modelContext.save()
        } catch {
            log.error("[ChatViewModel] Failed to save after appending message: \(error)")
        }
    }

    private func updateConversationMeta() {
        conversation.modelName = selectedModel?.name
        do {
            try modelContext.save()
        } catch {
            log.error("[ChatViewModel] Failed to save conversation meta: \(error)")
        }
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

}

func userFacingError(for error: Error, fallback: String) -> String {
    if error is CancellationError { return "Request cancelled." }
    if let proxyError = error as? ProxyError,
       let message = proxyError.errorDescription, !message.isEmpty {
        return message
    }
    let msg = (error as NSError).localizedDescription
    if !msg.isEmpty, msg != "(null)" { return msg }
    return fallback
}

struct Message: Identifiable {
    let id = UUID()
    let role: String
    let content: String
}

