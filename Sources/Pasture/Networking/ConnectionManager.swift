import Foundation
import Loom
import LoomKit

/// Central state manager for the Loom P2P connection to Pasture for Mac.
/// Handles discovery, auto-connect/reconnect, and the request/response wire protocol.
@MainActor
final class ConnectionManager: ObservableObject {
    @Published private(set) var state: ConnectionState = .discovering
    @Published private(set) var installedModels: [OllamaModel] = []
    @Published private(set) var availableHelpers: [LoomPeerSnapshot] = []
    @Published private(set) var connectedPeerID: UUID?
    @Published private(set) var hasEverConnected = false
    @Published private(set) var diagnostics = ConnectionDiagnostics()

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    private let loomContext: LoomContext
    private var connection: LoomConnectionHandle?
    private var discoveryTask: Task<Void, Never>?
    private var peerRefreshTask: Task<Void, Never>?
    private var listenTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = ConnectionRuntimePolicy.maxReconnectAttempts
    private let requestTimeoutNanoseconds = ConnectionRuntimePolicy.requestTimeoutNanoseconds
    private var lastConnectedPeerName: String?
    private var preferredPeerID: UUID?

    private var pendingResponses: [String: CheckedContinuation<ProxyResponse, Error>] = [:]
    private var responseTimeoutTasks: [String: Task<Void, Never>] = [:]
    private var chatContinuations: [String: AsyncThrowingStream<String, Error>.Continuation] = [:]
    private var pullContinuations: [String: AsyncThrowingStream<PullProgress, Error>.Continuation] = [:]

    enum ConnectionState: Equatable {
        case discovering
        case connecting(peerName: String)
        case reconnecting(peerName: String?, attempt: Int)
        case connected(peerName: String)
        case failed(String)
    }

    private enum DefaultsKeys {
        static let hasEverConnected = "pasture.connection.hasEverConnected"
        static let preferredPeerID = "pasture.connection.preferredPeerID"
        static let preferredPeerName = "pasture.connection.preferredPeerName"
    }

    init(loomContext: LoomContext) {
        self.loomContext = loomContext
        let defaults = UserDefaults.standard
        self.hasEverConnected = defaults.bool(forKey: DefaultsKeys.hasEverConnected)
        self.lastConnectedPeerName = defaults.string(forKey: DefaultsKeys.preferredPeerName)
        if let rawPeerID = defaults.string(forKey: DefaultsKeys.preferredPeerID) {
            self.preferredPeerID = UUID(uuidString: rawPeerID)
        }
        recordEvent("Connection manager initialized.")
    }

    deinit {
        discoveryTask?.cancel()
        peerRefreshTask?.cancel()
        listenTask?.cancel()
        reconnectTask?.cancel()
        for task in responseTimeoutTasks.values {
            task.cancel()
        }
        responseTimeoutTasks.removeAll()
    }

    // MARK: - Lifecycle

    func startDiscovery(resetReconnectAttempts: Bool = true) async {
        diagnostics.discoveryStarts += 1
        recordEvent("Starting discovery.")
        if case .connected(_) = state {
            recordEvent("Discovery skipped because already connected.")
            return
        }

        if resetReconnectAttempts {
            reconnectAttempt = 0
            reconnectTask?.cancel()
            reconnectTask = nil
        }

        do {
            try await loomContext.start()
            await loomContext.refreshPeers()
            state = .discovering
            availableHelpers = helperPeers()
            startPeerRefreshLoopIfNeeded()
            recordEvent("Discovery started with \(availableHelpers.count) helper(s) visible.")

            if discoveryTask == nil {
                discoveryTask = Task { [weak self] in
                    await self?.runDiscoveryLoop()
                }
            }
        } catch {
            state = .failed("Could not start local discovery: \(error.localizedDescription)")
            recordError("Discovery failed: \(error.localizedDescription)")
        }
    }

    private func startPeerRefreshLoopIfNeeded() {
        guard peerRefreshTask == nil else { return }

        peerRefreshTask = Task { [weak self] in
            await self?.runPeerRefreshLoop()
        }
    }

    private func runPeerRefreshLoop() async {
        defer { peerRefreshTask = nil }

        while !Task.isCancelled {
            await loomContext.refreshPeers()
            availableHelpers = helperPeers()
            diagnostics.peerRefreshes += 1
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private func runDiscoveryLoop() async {
        defer { discoveryTask = nil }

        while !Task.isCancelled {
            let helpers = helperPeers()
            availableHelpers = helpers
            if let target = autoConnectTarget(from: helpers) {
                await connect(to: target)
                return
            }

            await loomContext.refreshPeers()
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
    }

    private func helperPeers() -> [LoomPeerSnapshot] {
        loomContext.peers
            .filter {
                $0.deviceType == .mac
                    && $0.advertisement.metadata["service"] == "pasture"
            }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func autoConnectTarget(from helpers: [LoomPeerSnapshot]) -> LoomPeerSnapshot? {
        guard !helpers.isEmpty else { return nil }

        if let preferredPeerID,
           let preferredPeer = helpers.first(where: { $0.id == preferredPeerID }) {
            return preferredPeer
        }

        if let lastConnectedPeerName,
           let namedPeer = helpers.first(where: {
               $0.name.compare(lastConnectedPeerName, options: .caseInsensitive) == .orderedSame
           }) {
            return namedPeer
        }

        if helpers.count == 1 {
            return helpers[0]
        }

        return helpers.first(where: \.isNearby) ?? helpers.first
    }

    private func connect(to peer: LoomPeerSnapshot) async {
        discoveryTask?.cancel()
        discoveryTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        diagnostics.connectAttempts += 1
        recordEvent("Connecting to \(peer.name).")

        if let activeConnection = connection {
            await activeConnection.disconnect()
            connection = nil
            connectedPeerID = nil
            finishActiveStreams()
            failPendingResponses(with: ProxyError.notConnected)
            diagnostics.disconnects += 1
            recordEvent("Closed previous connection before reconnecting.")
        }

        state = .connecting(peerName: peer.name)

        do {
            let newConnection = try await loomContext.connect(peer)
            connection = newConnection
            connectedPeerID = peer.id
            state = .connected(peerName: peer.name)
            rememberPreferredPeer(peer)
            hasEverConnected = true
            UserDefaults.standard.set(true, forKey: DefaultsKeys.hasEverConnected)
            reconnectAttempt = 0
            startListening(on: newConnection)
            diagnostics.connectSuccesses += 1
            recordEvent("Connected to \(peer.name).")

            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await self.fetchModels()
                } catch {
                    // Model refresh is best-effort on connect; chat can still proceed.
                    print("[ConnectionManager] Initial model refresh failed: \(error)")
                    self.recordError("Initial model refresh failed: \(error.localizedDescription)")
                }
            }
        } catch {
            connectedPeerID = nil
            state = .failed("Could not connect to \(peer.name): \(error.localizedDescription)")
            recordError("Connect failed for \(peer.name): \(error.localizedDescription)")
            scheduleReconnectIfNeeded()
        }
    }

    private func startListening(on activeConnection: LoomConnectionHandle) {
        listenTask?.cancel()
        listenTask = Task { [weak self] in
            guard let self else { return }

            let expectedConnectionID = await activeConnection.id
            for await data in activeConnection.messages {
                await self.processIncomingData(data)
            }

            await self.connectionDidEnd(expectedConnectionID: expectedConnectionID)
        }
    }

    private func processIncomingData(_ data: Data) {
        guard let response = try? JSONDecoder().decode(ProxyResponse.self, from: data) else {
            diagnostics.responseDecodeFailures += 1
            recordError("Failed to decode response payload from helper.")
            return
        }
        diagnostics.responsesReceived += 1

        if let pending = pendingResponses.removeValue(forKey: response.id) {
            cancelRequestTimeout(for: response.id)
            if let error = response.errorMessage {
                diagnostics.remoteErrors += 1
                recordError("Remote error for request \(response.id): \(error)")
                pending.resume(throwing: ProxyError.remote(error))
            } else {
                pending.resume(returning: response)
            }
        }

        if let chatContinuation = chatContinuations[response.id] {
            if let error = response.errorMessage {
                diagnostics.remoteErrors += 1
                recordError("Chat stream error \(response.id): \(error)")
                chatContinuation.finish(throwing: ProxyError.remote(error))
                chatContinuations.removeValue(forKey: response.id)
                return
            }

            if let token = response.token, !token.isEmpty {
                chatContinuation.yield(token)
            }
            if response.done {
                chatContinuation.finish()
                chatContinuations.removeValue(forKey: response.id)
            }
        }

        if let pullContinuation = pullContinuations[response.id] {
            if let error = response.errorMessage {
                diagnostics.remoteErrors += 1
                recordError("Pull stream error \(response.id): \(error)")
                pullContinuation.finish(throwing: ProxyError.remote(error))
                pullContinuations.removeValue(forKey: response.id)
                return
            }

            if let progress = response.pullProgress {
                pullContinuation.yield(progress)
            }
            if response.done {
                pullContinuation.finish()
                pullContinuations.removeValue(forKey: response.id)
            }
        }
    }

    private func connectionDidEnd(expectedConnectionID: UUID) async {
        guard let activeConnection = connection else { return }
        let activeID = await activeConnection.id
        guard activeID == expectedConnectionID else { return }

        connection = nil
        connectedPeerID = nil
        finishActiveStreams()
        failPendingResponses(with: ProxyError.notConnected)
        diagnostics.disconnects += 1
        recordEvent("Connection ended unexpectedly. Scheduling reconnect.")

        scheduleReconnectIfNeeded()
    }

    func refreshAvailableHelpers() async {
        await loomContext.refreshPeers()
        availableHelpers = helperPeers()
        recordEvent("Manual helper refresh found \(availableHelpers.count) helper(s).")
    }

    func connectToHelper(peerID: UUID) async {
        let currentHelpers = helperPeers()
        availableHelpers = currentHelpers

        guard let target = currentHelpers.first(where: { $0.id == peerID }) else {
            state = .failed("That Mac is no longer available. Please refresh and try again.")
            recordError("Selected helper disappeared before connect.")
            return
        }

        await connect(to: target)
    }

    // MARK: - API

    func fetchModels() async throws {
        let response = try await sendRequest(
            ProxyRequest(id: UUID().uuidString, type: .tags)
        )
        installedModels = (response.models ?? []).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        recordEvent("Fetched \(installedModels.count) installed model(s).")
    }

    func delete(model: String) async throws {
        _ = try await sendRequest(
            ProxyRequest(id: UUID().uuidString, type: .delete, model: model)
        )
        recordEvent("Deleted model \(model). Refreshing model list.")
        try await fetchModels()
    }

    func chat(model: String, messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        let id = UUID().uuidString
        let request = ProxyRequest(id: id, type: .chat, model: model, messages: messages)
        recordEvent("Chat request started for model \(model).")

        return AsyncThrowingStream { continuation in
            Task { @MainActor [weak self] in
                guard let self else {
                    continuation.finish(throwing: ProxyError.notConnected)
                    return
                }
                guard let activeConnection = self.connection else {
                    continuation.finish(throwing: ProxyError.notConnected)
                    return
                }

                self.chatContinuations[id] = continuation
                do {
                    try await activeConnection.send(request)
                    self.diagnostics.requestsSent += 1
                } catch {
                    self.chatContinuations.removeValue(forKey: id)
                    self.recordError("Failed to send chat request: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { [weak self] termination in
                Task { @MainActor in
                    self?.chatContinuations.removeValue(forKey: id)
                    if case .cancelled = termination {
                        self?.diagnostics.chatStreamCancellations += 1
                        self?.recordEvent("Chat stream cancelled by client.")
                    }
                }
            }
        }
    }

    func pull(model: String) -> AsyncThrowingStream<PullProgress, Error> {
        let id = UUID().uuidString
        let request = ProxyRequest(id: id, type: .pull, model: model)
        recordEvent("Pull request started for model \(model).")

        return AsyncThrowingStream { continuation in
            Task { @MainActor [weak self] in
                guard let self else {
                    continuation.finish(throwing: ProxyError.notConnected)
                    return
                }
                guard let activeConnection = self.connection else {
                    continuation.finish(throwing: ProxyError.notConnected)
                    return
                }

                self.pullContinuations[id] = continuation
                do {
                    try await activeConnection.send(request)
                    self.diagnostics.requestsSent += 1
                } catch {
                    self.pullContinuations.removeValue(forKey: id)
                    self.recordError("Failed to send pull request: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { [weak self] termination in
                Task { @MainActor in
                    guard let self else { return }
                    self.pullContinuations.removeValue(forKey: id)
                    if case .cancelled = termination {
                        self.diagnostics.pullStreamCancellations += 1
                        self.recordEvent("Pull stream cancelled by client.")
                        await self.sendCancelRequest(for: id)
                    }
                }
            }
        }
    }

    // MARK: - Internal

    private func sendRequest(_ request: ProxyRequest) async throws -> ProxyResponse {
        guard let activeConnection = connection else { throw ProxyError.notConnected }
        diagnostics.requestsSent += 1

        return try await withCheckedThrowingContinuation { continuation in
            pendingResponses[request.id] = continuation
            scheduleRequestTimeout(for: request.id)

            Task { @MainActor [weak self] in
                guard let self else {
                    continuation.resume(throwing: ProxyError.notConnected)
                    return
                }

                do {
                    try await activeConnection.send(request)
                } catch {
                    self.cancelRequestTimeout(for: request.id)
                    if let pending = self.pendingResponses.removeValue(forKey: request.id) {
                        self.recordError("Failed to send request \(request.type.rawValue): \(error.localizedDescription)")
                        pending.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func finishActiveStreams(with error: Error = ProxyError.notConnected) {
        for continuation in chatContinuations.values {
            continuation.finish(throwing: error)
        }
        chatContinuations.removeAll()

        for continuation in pullContinuations.values {
            continuation.finish(throwing: error)
        }
        pullContinuations.removeAll()
    }

    private func failPendingResponses(with error: Error) {
        for task in responseTimeoutTasks.values {
            task.cancel()
        }
        responseTimeoutTasks.removeAll()

        let pending = pendingResponses
        pendingResponses.removeAll()
        for continuation in pending.values {
            continuation.resume(throwing: error)
        }
    }

    private func scheduleRequestTimeout(for requestID: String) {
        responseTimeoutTasks[requestID]?.cancel()
        responseTimeoutTasks[requestID] = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.requestTimeoutNanoseconds)
            guard !Task.isCancelled else { return }

            defer { self.responseTimeoutTasks.removeValue(forKey: requestID) }

            guard let pending = self.pendingResponses.removeValue(forKey: requestID) else {
                return
            }
            self.diagnostics.requestTimeouts += 1
            self.recordError("Request \(requestID) timed out.")
            pending.resume(throwing: ProxyError.timeout)
        }
    }

    private func cancelRequestTimeout(for requestID: String) {
        responseTimeoutTasks[requestID]?.cancel()
        responseTimeoutTasks.removeValue(forKey: requestID)
    }

    private func rememberPreferredPeer(_ peer: LoomPeerSnapshot) {
        preferredPeerID = peer.id
        lastConnectedPeerName = peer.name

        let defaults = UserDefaults.standard
        defaults.set(peer.id.uuidString, forKey: DefaultsKeys.preferredPeerID)
        defaults.set(peer.name, forKey: DefaultsKeys.preferredPeerName)
    }

    private func scheduleReconnectIfNeeded() {
        guard ConnectionRuntimePolicy.shouldScheduleReconnect(
            hasEverConnected: hasEverConnected,
            reconnectAttempt: reconnectAttempt,
            maxReconnectAttempts: maxReconnectAttempts
        ) else {
            if !hasEverConnected {
                return
            }
            state = .failed("Couldn’t reconnect to your Mac automatically. Tap Try Again.")
            diagnostics.reconnectExhausted += 1
            recordError("Reconnect attempts exhausted.")
            return
        }

        reconnectAttempt += 1
        diagnostics.reconnectSchedules += 1
        state = .reconnecting(peerName: lastConnectedPeerName, attempt: reconnectAttempt)
        recordEvent("Reconnect attempt \(reconnectAttempt) scheduled.")

        let delaySeconds = ConnectionRuntimePolicy.delaySeconds(forReconnectAttempt: reconnectAttempt)

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            await self.startDiscovery(resetReconnectAttempts: false)
            self.reconnectTask = nil
        }
    }

    private func sendCancelRequest(for requestID: String) async {
        guard let activeConnection = connection else { return }
        let cancelRequest = ProxyRequest.cancelRequest(targetRequestID: requestID)
        try? await activeConnection.send(cancelRequest)
        diagnostics.requestsSent += 1
        recordEvent("Sent cancel control request for \(requestID).")
    }

    func clearDiagnostics() {
        diagnostics = ConnectionDiagnostics()
        recordEvent("Diagnostics reset.")
    }

    private func recordEvent(
        _ message: String,
        level: ConnectionDiagnosticLevel = .info
    ) {
        diagnostics.lastEventAt = Date()
        if level == .error {
            diagnostics.lastError = message
        }

        diagnostics.recentEvents.append(
            ConnectionDiagnosticEvent(
                timestamp: Date(),
                level: level,
                message: message
            )
        )

        let limit = 40
        if diagnostics.recentEvents.count > limit {
            diagnostics.recentEvents.removeFirst(diagnostics.recentEvents.count - limit)
        }
    }

    private func recordError(_ message: String) {
        recordEvent(message, level: .error)
    }
}

enum ConnectionDiagnosticLevel: String, Codable, Sendable {
    case info
    case warning
    case error
}

struct ConnectionDiagnosticEvent: Identifiable, Equatable, Sendable {
    let id = UUID()
    let timestamp: Date
    let level: ConnectionDiagnosticLevel
    let message: String
}

struct ConnectionDiagnostics: Equatable, Sendable {
    var discoveryStarts = 0
    var peerRefreshes = 0
    var connectAttempts = 0
    var connectSuccesses = 0
    var reconnectSchedules = 0
    var reconnectExhausted = 0
    var disconnects = 0
    var requestsSent = 0
    var responsesReceived = 0
    var responseDecodeFailures = 0
    var requestTimeouts = 0
    var remoteErrors = 0
    var chatStreamCancellations = 0
    var pullStreamCancellations = 0
    var lastError: String?
    var lastEventAt: Date?
    var recentEvents: [ConnectionDiagnosticEvent] = []
}

// MARK: - Errors

enum ProxyError: Error {
    case notConnected
    case timeout
    case remote(String)
}

extension ProxyError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to your Mac."
        case .timeout:
            return "Request timed out while waiting for your Mac."
        case .remote(let message):
            return message
        }
    }
}

// MARK: - Wire protocol (mirrored from PastureHelper)

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

    static func cancelRequest(targetRequestID: String) -> ProxyRequest {
        ProxyRequest(
            id: UUID().uuidString,
            type: .cancel,
            targetRequestID: targetRequestID
        )
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

struct OllamaModel: Codable, Identifiable, Sendable, Hashable {
    var id: String { name }
    let name: String
    let size: Int64?
    let details: ModelDetails?

    struct ModelDetails: Codable, Sendable, Hashable {
        let family: String?
        let parameterSize: String?

        enum CodingKeys: String, CodingKey {
            case family
            case parameterSize = "parameter_size"
        }
    }
}

struct ChatMessage: Codable, Sendable {
    let role: String
    let content: String
}

struct PullProgress: Codable, Sendable {
    let status: String
    let total: Int64?
    let completed: Int64?

    var fraction: Double {
        guard let total, let completed, total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}

enum ConnectionRuntimePolicy {
    static let maxReconnectAttempts = 6
    static let requestTimeoutNanoseconds: UInt64 = 20_000_000_000

    static func shouldScheduleReconnect(
        hasEverConnected: Bool,
        reconnectAttempt: Int,
        maxReconnectAttempts: Int = maxReconnectAttempts
    ) -> Bool {
        guard hasEverConnected else { return false }
        return reconnectAttempt < maxReconnectAttempts
    }

    static func delaySeconds(forReconnectAttempt attempt: Int) -> Double {
        guard attempt > 0 else { return 1.0 }
        return min(8.0, pow(2.0, Double(attempt - 1)))
    }
}
