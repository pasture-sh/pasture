import Foundation
import LoomKit

/// Receives structured requests from the iOS app over LoomKit
/// and forwards them to the local Ollama API, streaming responses back.
actor OllamaProxy {
    private var runningRequestTasks: [String: Task<Void, Never>] = [:]
    private var diagnostics = ProxyDiagnosticsSnapshot()

    func handle(connection: LoomConnectionHandle) async {
        let peerName = await connection.peer.name
        diagnostics.connectionsHandled += 1
        recordEvent("Incoming connection from \(peerName).")

        defer {
            cancelAllRunningRequests()
            recordEvent("Connection from \(peerName) ended.")
        }

        for await data in connection.messages {
            diagnostics.messagesReceived += 1
            guard let request = try? JSONDecoder().decode(ProxyRequest.self, from: data) else {
                diagnostics.requestDecodeFailures += 1
                recordError("Failed to decode incoming request payload.")
                continue
            }
            diagnostics.requestsReceived += 1
            await route(request: request, connection: connection)
        }
    }

    private func route(request: ProxyRequest, connection: LoomConnectionHandle) async {
        incrementRequestCounter(for: request.type)

        switch request.type {
        case .cancel:
            await handleCancel(request: request, connection: connection)

        case .tags:
            launchRequestTask(id: request.id) { proxy in
                await proxy.handleTags(id: request.id, connection: connection)
            }
        case .chat:
            guard let model = request.model, let messages = request.messages else {
                await sendError(id: request.id, message: "Missing chat request fields.", connection: connection)
                return
            }
            launchRequestTask(id: request.id) { proxy in
                await proxy.handleChat(
                    id: request.id,
                    model: model,
                    messages: messages,
                    connection: connection
                )
            }

        case .pull:
            guard let model = request.model else {
                await sendError(id: request.id, message: "Missing model for pull request.", connection: connection)
                return
            }
            launchRequestTask(id: request.id) { proxy in
                await proxy.handlePull(id: request.id, model: model, connection: connection)
            }

        case .delete:
            guard let model = request.model else {
                await sendError(id: request.id, message: "Missing model for delete request.", connection: connection)
                return
            }
            launchRequestTask(id: request.id) { proxy in
                await proxy.handleDelete(id: request.id, model: model, connection: connection)
            }
        }
    }

    private func handleCancel(request: ProxyRequest, connection: LoomConnectionHandle) async {
        guard let targetRequestID = request.targetRequestID else {
            diagnostics.remoteProtocolErrors += 1
            await sendError(
                id: request.id,
                message: "Missing request id to cancel.",
                connection: connection
            )
            return
        }

        if let activeTask = runningRequestTasks.removeValue(forKey: targetRequestID) {
            activeTask.cancel()
            diagnostics.cancellationsRequested += 1
            recordEvent("Cancelled active request \(targetRequestID).")
        } else {
            recordEvent("Cancel request \(targetRequestID) received, but no active task matched.", level: .warning)
        }

        await send(
            ProxyResponse(id: request.id, type: .cancel, done: true),
            connection: connection
        )
    }

    private func launchRequestTask(
        id: String,
        operation: @escaping @Sendable (OllamaProxy) async -> Void
    ) {
        runningRequestTasks[id]?.cancel()

        let task = Task { [weak self] in
            guard let self else { return }
            await operation(self)
            await self.finishRequestTask(id: id)
        }

        runningRequestTasks[id] = task
        diagnostics.activeTaskHighWatermark = max(diagnostics.activeTaskHighWatermark, runningRequestTasks.count)
    }

    private func finishRequestTask(id: String) {
        runningRequestTasks.removeValue(forKey: id)
    }

    private func cancelAllRunningRequests() {
        let tasks = runningRequestTasks.values
        runningRequestTasks.removeAll()
        for task in tasks {
            task.cancel()
        }
        if !tasks.isEmpty {
            diagnostics.cancellationsRequested += tasks.count
            recordEvent("Cancelled \(tasks.count) active request task(s) on connection teardown.")
        }
    }

    private func handleTags(id: String, connection: LoomConnectionHandle) async {
        do {
            let models = try await OllamaAPIClient.shared.fetchTags()
            await send(
                ProxyResponse(id: id, type: .tags, models: models, done: true),
                connection: connection
            )
        } catch {
            diagnostics.handlerErrors += 1
            await sendError(id: id, message: error.localizedDescription, connection: connection)
        }
    }

    private func handleChat(
        id: String,
        model: String,
        messages: [ChatMessage],
        connection: LoomConnectionHandle
    ) async {
        let stream = await OllamaAPIClient.shared.chat(model: model, messages: messages)

        do {
            for try await token in stream {
                await send(
                    ProxyResponse(id: id, type: .chat, token: token, done: false),
                    connection: connection
                )
            }

            await send(
                ProxyResponse(id: id, type: .chat, done: true),
                connection: connection
            )
        } catch is CancellationError {
            // Request was cancelled by the client.
            diagnostics.streamCancellations += 1
            recordEvent("Chat request \(id) cancelled.")
        } catch {
            diagnostics.handlerErrors += 1
            await sendError(id: id, message: error.localizedDescription, connection: connection)
        }
    }

    private func handlePull(
        id: String,
        model: String,
        connection: LoomConnectionHandle
    ) async {
        let stream = await OllamaAPIClient.shared.pull(model: model)
        var completedSuccessfully = false

        do {
            for try await progress in stream {
                let didFinish = progress.status == "success"
                completedSuccessfully = completedSuccessfully || didFinish
                await send(
                    ProxyResponse(
                        id: id,
                        type: .pull,
                        pullProgress: progress,
                        done: didFinish
                    ),
                    connection: connection
                )
            }

            if !completedSuccessfully {
                diagnostics.handlerErrors += 1
                await sendError(
                    id: id,
                    message: "Model download ended unexpectedly. Please try again.",
                    connection: connection
                )
            }
        } catch is CancellationError {
            // Request was cancelled by the client.
            diagnostics.streamCancellations += 1
            recordEvent("Pull request \(id) cancelled.")
        } catch {
            diagnostics.handlerErrors += 1
            await sendError(id: id, message: error.localizedDescription, connection: connection)
        }
    }

    private func handleDelete(
        id: String,
        model: String,
        connection: LoomConnectionHandle
    ) async {
        do {
            try await OllamaAPIClient.shared.delete(model: model)
            await send(
                ProxyResponse(id: id, type: .delete, done: true),
                connection: connection
            )
        } catch {
            diagnostics.handlerErrors += 1
            await sendError(id: id, message: error.localizedDescription, connection: connection)
        }
    }

    private func sendError(
        id: String,
        message: String,
        connection: LoomConnectionHandle
    ) async {
        diagnostics.errorsSent += 1
        recordError("Request \(id) failed: \(message)")
        await send(
            ProxyResponse(id: id, type: .error, errorMessage: message, done: true),
            connection: connection
        )
    }

    private func send(
        _ response: ProxyResponse,
        connection: LoomConnectionHandle
    ) async {
        do {
            try await connection.send(response)
            diagnostics.responsesSent += 1
        } catch {
            diagnostics.responseSendFailures += 1
            recordError("Failed to send response \(response.type.rawValue) for \(response.id): \(error.localizedDescription)")
            print("[OllamaProxy] Failed to send response: \(error)")
        }
    }

    func diagnosticsSnapshot() -> ProxyDiagnosticsSnapshot {
        var snapshot = diagnostics
        snapshot.activeRequests = runningRequestTasks.count
        return snapshot
    }

    func resetDiagnostics() {
        diagnostics = ProxyDiagnosticsSnapshot()
        recordEvent("Proxy diagnostics reset.")
    }

    private func incrementRequestCounter(for type: ProxyRequestType) {
        switch type {
        case .tags:
            diagnostics.tagsRequests += 1
        case .chat:
            diagnostics.chatRequests += 1
        case .pull:
            diagnostics.pullRequests += 1
        case .delete:
            diagnostics.deleteRequests += 1
        case .cancel:
            diagnostics.cancelRequests += 1
        }
    }

    private func recordEvent(_ message: String, level: ProxyDiagnosticLevel = .info) {
        diagnostics.recentEvents.append(
            ProxyDiagnosticEvent(
                timestamp: Date(),
                level: level,
                message: message
            )
        )

        let limit = 40
        if diagnostics.recentEvents.count > limit {
            diagnostics.recentEvents.removeFirst(diagnostics.recentEvents.count - limit)
        }

        if level == .error {
            diagnostics.lastError = message
        }
    }

    private func recordError(_ message: String) {
        recordEvent(message, level: .error)
    }
}

enum ProxyDiagnosticLevel: String, Codable, Sendable {
    case info
    case warning
    case error
}

struct ProxyDiagnosticEvent: Identifiable, Equatable, Sendable {
    let id = UUID()
    let timestamp: Date
    let level: ProxyDiagnosticLevel
    let message: String
}

struct ProxyDiagnosticsSnapshot: Equatable, Sendable {
    var connectionsHandled = 0
    var messagesReceived = 0
    var requestsReceived = 0
    var tagsRequests = 0
    var chatRequests = 0
    var pullRequests = 0
    var deleteRequests = 0
    var cancelRequests = 0
    var activeRequests = 0
    var activeTaskHighWatermark = 0
    var cancellationsRequested = 0
    var streamCancellations = 0
    var requestDecodeFailures = 0
    var remoteProtocolErrors = 0
    var handlerErrors = 0
    var errorsSent = 0
    var responsesSent = 0
    var responseSendFailures = 0
    var lastError: String?
    var recentEvents: [ProxyDiagnosticEvent] = []
}

// MARK: - Wire protocol

enum ProxyRequestType: String, Codable, Sendable {
    case tags, chat, pull, delete, cancel
}

enum ProxyResponseType: String, Codable, Sendable {
    case tags, chat, pull, delete, cancel, error
}

struct ProxyRequest: Codable, Sendable {
    let id: String
    let type: ProxyRequestType
    let model: String?
    let messages: [ChatMessage]?
    let targetRequestID: String?

    init(
        id: String,
        type: ProxyRequestType,
        model: String? = nil,
        messages: [ChatMessage]? = nil,
        targetRequestID: String? = nil
    ) {
        self.id = id
        self.type = type
        self.model = model
        self.messages = messages
        self.targetRequestID = targetRequestID
    }
}

struct ProxyResponse: Codable, Sendable {
    let id: String
    let type: ProxyResponseType
    var models: [OllamaModel]?
    var token: String?
    var pullProgress: PullProgress?
    var errorMessage: String?
    var done: Bool

    init(
        id: String,
        type: ProxyResponseType,
        models: [OllamaModel]? = nil,
        token: String? = nil,
        pullProgress: PullProgress? = nil,
        errorMessage: String? = nil,
        done: Bool
    ) {
        self.id = id
        self.type = type
        self.models = models
        self.token = token
        self.pullProgress = pullProgress
        self.errorMessage = errorMessage
        self.done = done
    }
}
