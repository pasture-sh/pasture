import Foundation
import Loom
import LoomKit
import MultipeerConnectivity
import PastureShared

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
    private let mpcBrowser = MPCBrowser()
    private var connection: PeerChannelAdapter?
    private var discoveryTask: Task<Void, Never>?
    private var peerRefreshTask: Task<Void, Never>?
    private var listenTask: Task<Void, Never>?
    private var connectionEventTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var keepaliveTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = ConnectionRuntimePolicy.maxReconnectAttempts
    private let requestTimeoutNanoseconds = ConnectionRuntimePolicy.requestTimeoutNanoseconds
    private var lastConnectedPeerName: String?
    private var preferredPeerID: UUID?
    private var inFlightModelFetch: Task<[OllamaModel], Error>?

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
        if let runtimeWarning = PastureLoomRuntimeConfiguration.runtimeWarning() {
            recordEvent(runtimeWarning, level: .warning)
        }
    }

    deinit {
        discoveryTask?.cancel()
        peerRefreshTask?.cancel()
        listenTask?.cancel()
        connectionEventTask?.cancel()
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
            mpcBrowser.start()
            state = .discovering
            await refreshAndSyncPeers(source: "startup")
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
            await refreshAndSyncPeers(source: "peer-refresh-loop")
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private func runDiscoveryLoop() async {
        defer { discoveryTask = nil }

        // Count loops without a Loom peer. After ~3 s (5 × ~600 ms), try MPC fallback.
        var loomTimeoutLoops = 0
        // Require the target to be visible for 3 consecutive loops (~1.6 s) before connecting.
        // Bonjour can advertise a peer before its TCP endpoint is connectable (e.g. right after
        // PastureHelper restarts), causing an immediate "could not resolve peer" failure.
        var peerStableLoops = 0

        while !Task.isCancelled {
            syncPeersFromContext(source: "discovery-loop")

            // Prefer Loom (Bonjour + Tailscale + CloudKit trust).
            if let target = autoConnectTarget(from: availableHelpers) {
                peerStableLoops += 1
                if peerStableLoops >= 3 {
                    await connect(to: .loom(target))
                    return
                }
            } else {
                peerStableLoops = 0
                loomTimeoutLoops += 1
            }

            // Fall back to MPC after 5 loops without a Loom peer.
            if loomTimeoutLoops >= 5, let mpcPeer = mpcBrowser.discoveredPeers.first {
                recordEvent("No Loom peer found after \(loomTimeoutLoops) loops. Trying MPC fallback.")
                await connect(to: .mpc(mpcPeer))
                return
            }

            await refreshAndSyncPeers(source: "discovery-loop")
            try? await Task.sleep(nanoseconds: 550_000_000)
        }
    }

    private enum DiscoveredHelper {
        case loom(LoomPeerSnapshot)
        case mpc(MCPeerID)
    }

    private func helperPeers() -> [LoomPeerSnapshot] {
        loomContext.peers
            .filter { $0.deviceType == .mac || $0.deviceType == .unknown }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func autoConnectTarget(from helpers: [LoomPeerSnapshot]) -> LoomPeerSnapshot? {
        // Returns the best Loom peer to auto-connect to, or nil if none are available.
        guard !helpers.isEmpty else { return nil }

        if let preferredPeerID,
           let preferredPeer = helpers.first(where: { $0.id.deviceID == preferredPeerID }) {
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

    private func connect(to target: DiscoveredHelper) async {
        discoveryTask?.cancel()
        discoveryTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        diagnostics.connectAttempts += 1

        let targetName: String
        switch target {
        case .loom(let peer): targetName = peer.name
        case .mpc(let peer): targetName = peer.displayName
        }
        recordEvent("Connecting to \(targetName).")

        if let activeConnection = connection {
            await activeConnection.disconnect()
            connection = nil
            connectedPeerID = nil
            listenTask?.cancel()
            listenTask = nil
            connectionEventTask?.cancel()
            connectionEventTask = nil
            finishActiveStreams()
            failPendingResponses(with: ProxyError.notConnected)
            diagnostics.disconnects += 1
            recordEvent("Closed previous connection before reconnecting.")
        }

        state = .connecting(peerName: targetName)

        do {
            let channel: PeerChannelAdapter
            switch target {
            case .loom(let peer):
                let handle = try await loomContext.connect(peer)
                channel = await makeLoomChannelAdapter(handle: handle, peer: peer)
                connectedPeerID = peer.id.deviceID
                rememberPreferredPeer(peer)
                mpcBrowser.stop()
            case .mpc(let peer):
                channel = try await mpcBrowser.connect(to: peer)
                connectedPeerID = nil
            }

            connection = channel
            state = .connected(peerName: targetName)
            hasEverConnected = true
            UserDefaults.standard.set(true, forKey: DefaultsKeys.hasEverConnected)
            reconnectAttempt = 0
            startListening(on: channel)
            startMonitoringConnectionEvents(on: channel)
            startKeepalive(on: channel)
            diagnostics.connectSuccesses += 1
            recordEvent("Connected to \(targetName) via \(channel.transportType).")

            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await self.fetchModels()
                } catch {
                    self.recordError("Initial model refresh failed: \(error.localizedDescription)")
                }
            }
        } catch {
            connectedPeerID = nil
            state = .failed("Could not connect to \(targetName): \(error.localizedDescription)")
            recordError("Connect failed for \(targetName): \(error.localizedDescription)")
            scheduleReconnectIfNeeded()
        }
    }

    /// Wraps a LoomConnectionHandle in a PeerChannelAdapter, bridging its event stream.
    private func makeLoomChannelAdapter(handle: LoomConnectionHandle, peer: LoomPeerSnapshot) async -> PeerChannelAdapter {
        let (eventsStream, eventsCont) = AsyncStream.makeStream(of: PeerChannelEvent.self)
        Task {
            for await event in handle.events {
                if case .disconnected = event {
                    eventsCont.yield(.disconnected)
                    eventsCont.finish()
                    return
                }
            }
            eventsCont.finish()
        }
        return PeerChannelAdapter(
            id: await handle.id,
            peerName: peer.name,
            transportType: .loom,
            messages: handle.messages,
            events: eventsStream,
            send: { data in try await handle.send(data) },
            disconnect: { await handle.disconnect() }
        )
    }

    private func startListening(on channel: PeerChannelAdapter) {
        listenTask?.cancel()
        listenTask = Task { [weak self] in
            guard let self else { return }

            let expectedConnectionID = channel.id
            for await data in channel.messages {
                self.processIncomingData(data)
            }

            await self.connectionDidEnd(expectedConnectionID: expectedConnectionID)
        }
    }

    private func startMonitoringConnectionEvents(on channel: PeerChannelAdapter) {
        connectionEventTask?.cancel()
        connectionEventTask = Task { [weak self] in
            guard let self else { return }

            let expectedConnectionID = channel.id
            for await event in channel.events {
                if case .disconnected = event {
                    await self.connectionDidEnd(expectedConnectionID: expectedConnectionID)
                    return
                }
            }
        }
    }

    private func startKeepalive(on channel: PeerChannelAdapter) {
        keepaliveTask?.cancel()
        keepaliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30s
                guard let self, !Task.isCancelled else { return }
                await self.checkConnectionHealth(expectedConnectionID: channel.id, transportType: channel.transportType)
            }
        }
    }

    private func isLoomConnectionLive(id: UUID) -> Bool {
        let state = loomContext.connections.first(where: { $0.id == id })?.state
        return state != nil && state != .disconnected && state != .failed
    }

    private func checkConnectionHealth(expectedConnectionID: UUID, transportType: PeerTransportType) async {
        guard isConnected else { return }
        if transportType == .loom, !isLoomConnectionLive(id: expectedConnectionID) {
            recordEvent("Keepalive: Loom connection gone — triggering reconnect.")
            await connectionDidEnd(expectedConnectionID: expectedConnectionID)
        }
        // MPC self-reports via its event stream; no proactive check needed.
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
        let activeID = activeConnection.id
        guard activeID == expectedConnectionID else { return }

        connection = nil
        connectedPeerID = nil
        listenTask?.cancel()
        listenTask = nil
        connectionEventTask?.cancel()
        connectionEventTask = nil
        keepaliveTask?.cancel()
        keepaliveTask = nil
        inFlightModelFetch?.cancel()
        inFlightModelFetch = nil
        finishActiveStreams()
        failPendingResponses(with: ProxyError.notConnected)
        diagnostics.disconnects += 1
        recordEvent("Connection ended unexpectedly. Scheduling reconnect.")

        scheduleReconnectIfNeeded()
    }

    func handleAppForeground() async {
        recordEvent("App returned to foreground.")

        if isConnected {
            // Force-restart peer refresh loop — iOS may have suspended the running task.
            peerRefreshTask?.cancel()
            peerRefreshTask = nil
            startPeerRefreshLoopIfNeeded()

            // For Loom connections, check whether Loom still considers this connection live.
            if let conn = connection, conn.transportType == .loom, !isLoomConnectionLive(id: conn.id) {
                await connectionDidEnd(expectedConnectionID: conn.id)
                return
            }
            // MPC connections self-report disconnection via their events stream — no extra check needed.

            // Connection appears live — kick a model fetch to verify against the Mac.
            // If the socket is stale, the send failure triggers reconnect automatically.
            Task { @MainActor [weak self] in
                try? await self?.fetchModels()
            }
            return
        }

        // Don't interrupt an in-progress connect attempt.
        if case .connecting = state { return }

        // Cancel any pending reconnect timer so it doesn't race the foreground-initiated restart.
        reconnectTask?.cancel()
        reconnectTask = nil
        // Discovering, stalled, failed, or reconnect-exhausted — cancel any suspended tasks and restart.
        discoveryTask?.cancel()
        discoveryTask = nil
        peerRefreshTask?.cancel()
        peerRefreshTask = nil
        await startDiscovery()
    }

    func refreshAvailableHelpers() async {
        await refreshAndSyncPeers(source: "manual-refresh")
        recordEvent("Manual helper refresh found \(availableHelpers.count) helper(s).")
    }

    func connectToHelper(peerID: LoomPeerID) async {
        reconnectAttempt = 0
        syncPeersFromContext(source: "manual-connect")
        let currentHelpers = availableHelpers

        guard let target = currentHelpers.first(where: { $0.id == peerID }) else {
            state = .failed("That Mac is no longer available. Please refresh and try again.")
            recordError("Selected helper disappeared before connect.")
            return
        }

        await connect(to: .loom(target))
    }

    // MARK: - API

    func fetchModels() async throws {
        let task: Task<[OllamaModel], Error>
        let createdNewTask: Bool

        if let inFlightModelFetch {
            task = inFlightModelFetch
            createdNewTask = false
            recordEvent("Reusing in-flight model fetch.")
        } else {
            let newTask = Task { @MainActor [weak self] () throws -> [OllamaModel] in
                guard let self else { throw ProxyError.notConnected }
                let response = try await self.sendRequest(
                    ProxyRequest(id: UUID().uuidString, type: .tags)
                )
                return (response.models ?? []).sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            }
            inFlightModelFetch = newTask
            task = newTask
            createdNewTask = true
        }

        defer { if createdNewTask { inFlightModelFetch = nil } }

        let models = try await task.value
        installedModels = models
        recordEvent("Fetched \(installedModels.count) installed model(s).")
    }

    func backup(filename: String, payload: String) async {
        guard let activeConnection = connection else { return }
        let request = ProxyRequest(id: UUID().uuidString, type: .backup, model: filename, payload: payload)
        do {
            try await activeConnection.send(request)
            diagnostics.requestsSent += 1
        } catch {
            // Backup is best-effort; silence failures.
        }
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
                continuation.onTermination = { [weak self] termination in
                    Task { @MainActor in
                        self?.chatContinuations.removeValue(forKey: id)
                        if case .cancelled = termination {
                            self?.diagnostics.chatStreamCancellations += 1
                            self?.recordEvent("Chat stream cancelled by client.")
                        }
                    }
                }
                do {
                    try await activeConnection.send(request)
                    self.diagnostics.requestsSent += 1
                } catch {
                    self.chatContinuations.removeValue(forKey: id)
                    self.recordError("Failed to send chat request: \(error.localizedDescription)")
                    await self.handleSendFailure(error, on: activeConnection, context: "chat")
                    continuation.finish(throwing: error)
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
                do {
                    try await activeConnection.send(request)
                    self.diagnostics.requestsSent += 1
                } catch {
                    self.pullContinuations.removeValue(forKey: id)
                    self.recordError("Failed to send pull request: \(error.localizedDescription)")
                    await self.handleSendFailure(error, on: activeConnection, context: "pull")
                    continuation.finish(throwing: error)
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
                    await self.handleSendFailure(error, on: activeConnection, context: request.type.rawValue)
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

            // Only tear down if no active streams would be collaterally killed.
            // A background model fetch timing out should not terminate an in-progress chat or download.
            guard self.chatContinuations.isEmpty, self.pullContinuations.isEmpty else { return }
            guard let conn = self.connection else { return }
            let connID = conn.id
            await self.connectionDidEnd(expectedConnectionID: connID)
        }
    }

    private func cancelRequestTimeout(for requestID: String) {
        responseTimeoutTasks[requestID]?.cancel()
        responseTimeoutTasks.removeValue(forKey: requestID)
    }

    private func rememberPreferredPeer(_ peer: LoomPeerSnapshot) {
        preferredPeerID = peer.id.deviceID
        lastConnectedPeerName = peer.name

        let defaults = UserDefaults.standard
        defaults.set(peer.id.deviceID.uuidString, forKey: DefaultsKeys.preferredPeerID)
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
            // Fast retries exhausted. Reset the counter and schedule a slower retry in 30s
            // rather than giving up — the Mac may just be sleeping or temporarily unreachable.
            diagnostics.reconnectExhausted += 1
            reconnectAttempt = 0
            state = .reconnecting(peerName: lastConnectedPeerName, attempt: 0)
            recordEvent("Fast reconnect attempts exhausted. Retrying in 30s.")
            reconnectTask?.cancel()
            reconnectTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let self, !Task.isCancelled else { return }
                await self.startDiscovery(resetReconnectAttempts: true)
                self.reconnectTask = nil
            }
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
        do {
            try await activeConnection.send(cancelRequest)
            diagnostics.requestsSent += 1
            recordEvent("Sent cancel control request for \(requestID).")
        } catch {
            recordError("Failed to send cancel request for \(requestID): \(error.localizedDescription)")
            await handleSendFailure(error, on: activeConnection, context: "cancel")
        }
    }

    private func handleSendFailure(
        _ error: Error,
        on channel: PeerChannelAdapter,
        context: String
    ) async {
        let shouldReconnect: Bool
        switch channel.transportType {
        case .loom:
            // Loom surfaces a closed socket as NWError ENOTCONN (code 57 / posix 57).
            let nsError = error as NSError
            shouldReconnect = nsError.domain == "Network.NWError" && nsError.code == ENOTCONN
        case .mpc:
            // Any MPC send failure indicates the session is gone.
            shouldReconnect = true
        }

        guard shouldReconnect else { return }

        recordEvent(
            "Detected closed \(channel.transportType) socket while sending \(context). Triggering reconnect.",
            level: .warning
        )

        await connectionDidEnd(expectedConnectionID: channel.id)
    }

    private func refreshAndSyncPeers(source: String) async {
        await loomContext.refreshPeers()
        diagnostics.peerRefreshes += 1

        // LoomContext applies snapshot updates asynchronously. A short delay avoids
        // reading the previous peer set immediately after requesting a refresh.
        try? await Task.sleep(nanoseconds: 250_000_000)
        syncPeersFromContext(source: source)
    }

    private func syncPeersFromContext(source: String) {
        let allPeers = loomContext.peers.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        let helpers = helperPeers()

        // Only update availableHelpers when the peer set actually changes.
        // Skip if the new list is empty but we already have entries —
        // Loom's peer browser can momentarily return zero peers mid-refresh cycle.
        let newIDs = helpers.map { $0.id }
        let currentIDs = availableHelpers.map { $0.id }
        if newIDs != currentIDs && (!helpers.isEmpty || availableHelpers.isEmpty) {
            availableHelpers = helpers
        }

        diagnostics.visiblePeerCount = allPeers.count
        diagnostics.visibleHelperCount = helpers.count

        let peerSummary = summarizePeers(allPeers)
        if peerSummary != diagnostics.lastPeerSnapshotSummary {
            diagnostics.lastPeerSnapshotSummary = peerSummary
            recordEvent("Peer snapshot (\(source)): \(peerSummary)")
        }

        let loomError = loomContext.lastError?.message
        if loomError != diagnostics.loomRuntimeError {
            diagnostics.loomRuntimeError = loomError
            if let loomError {
                recordEvent("Loom runtime warning (\(source)): \(loomError)", level: .warning)
            }
        }
    }

    private func summarizePeers(_ peers: [LoomPeerSnapshot]) -> String {
        guard !peers.isEmpty else { return "none" }

        return peers.map { peer in
            let sources = peer.sources.map(\.rawValue).sorted().joined(separator: "+")
            let service = peer.advertisement.metadata["service"] ?? "-"
            return "\(peer.name) [type=\(peer.deviceType.rawValue), nearby=\(peer.isNearby), service=\(service), sources=\(sources)]"
        }
        .joined(separator: " | ")
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

        let limit = 40
        if diagnostics.recentEvents.count >= limit {
            diagnostics.recentEvents.removeFirst()
        }
        diagnostics.recentEvents.append(
            ConnectionDiagnosticEvent(
                timestamp: Date(),
                level: level,
                message: message
            )
        )
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
    var visiblePeerCount = 0
    var visibleHelperCount = 0
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
    var loomRuntimeError: String?
    var lastPeerSnapshotSummary: String?
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
        guard attempt > 0 else { return 3.0 }
        // Minimum 3 s — fast retries below that hit Bonjour-advertised peers whose TCP
        // endpoint isn't connectable yet, causing repeated "could not resolve peer" failures.
        return min(8.0, max(3.0, pow(2.0, Double(attempt - 1))))
    }
}
