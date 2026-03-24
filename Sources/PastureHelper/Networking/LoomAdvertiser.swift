import Foundation
import LoomKit
import PastureShared

/// Manages the LoomKit context that advertises this Mac on the local network
/// and accepts incoming connections from the Pasture iOS app.
/// Also runs an MPCAdvertiser in parallel for offline/Bluetooth fallback.
@MainActor
final class LoomAdvertiser: ObservableObject {
    @Published private(set) var connectedPeerName: String?
    @Published private(set) var isAdvertising = false
    @Published private(set) var isPaused = false
    @Published private(set) var ollamaIsReachable = false
    @Published private(set) var diagnostics = HelperDiagnostics()

    private let loomContext: LoomContext
    private let proxy: OllamaProxy
    private let mpcAdvertiser = MPCAdvertiser()
    private var acceptTask: Task<Void, Never>?
    private var healthTask: Task<Void, Never>?
    private var connectionTasks: [UUID: [Task<Void, Never>]] = [:]
    private let defaults = UserDefaults.standard

    private enum DefaultsKeys {
        static let isDiscoveryPaused = "pasture.helper.discoveryPaused"
    }

    init(
        loomContext: LoomContext,
        proxy: OllamaProxy = OllamaProxy()
    ) {
        self.loomContext = loomContext
        self.proxy = proxy
        self.isPaused = defaults.bool(forKey: DefaultsKeys.isDiscoveryPaused)
        recordEvent("Helper advertiser initialized.")
        if let runtimeWarning = PastureLoomRuntimeConfiguration.runtimeWarning() {
            recordEvent(runtimeWarning, level: .warning)
        }
    }

    func start() async {
        diagnostics.startAttempts += 1
        recordEvent("Starting advertiser.")
        startHealthChecks()
        guard !isPaused else {
            recordEvent("Start skipped because discovery is paused.")
            return
        }
        guard acceptTask == nil else {
            recordEvent("Start skipped because advertiser is already running.")
            return
        }

        // Start MPC advertiser for offline/Bluetooth fallback.
        mpcAdvertiser.start { [weak self] channel in
            self?.acceptMPCChannel(channel)
        }

        do {
            try await loomContext.start()
            isAdvertising = true
            diagnostics.startSuccesses += 1
            recordEvent("Advertising started.")

            acceptTask = Task { [weak self] in
                guard let self else { return }

                for await connection in self.loomContext.incomingConnections {
                    let peerName = await connection.peer.name
                    let connectionID = await connection.id

                    // Bridge Loom events → PeerChannelEvent for uniform handling
                    let (eventsStream, eventsCont) = AsyncStream.makeStream(of: PeerChannelEvent.self)
                    Task {
                        for await event in connection.events {
                            if case .disconnected = event {
                                eventsCont.yield(.disconnected)
                                eventsCont.finish()
                                return
                            }
                        }
                        eventsCont.finish()
                    }

                    let channel = PeerChannelAdapter(
                        id: connectionID,
                        peerName: peerName,
                        transportType: .loom,
                        messages: connection.messages,
                        events: eventsStream,
                        send: { data in try await connection.send(data) },
                        disconnect: { await connection.disconnect() }
                    )

                    await MainActor.run {
                        // Ensure only one proxy handler runs at a time.
                        if !self.connectionTasks.isEmpty {
                            self.connectionTasks.values.forEach { $0.forEach { $0.cancel() } }
                            self.connectionTasks.removeAll()
                            self.recordEvent("Closed stale session before accepting new connection from \(peerName).")
                        }
                        self.connectedPeerName = peerName
                        self.diagnostics.incomingConnections += 1
                        self.recordEvent("Accepted Loom connection from \(peerName).")
                    }

                    await self.serveChannel(channel)
                }
            }
        } catch {
            diagnostics.startFailures += 1
            isAdvertising = false
            ollamaIsReachable = false
            recordError(userFacingStartErrorMessage(for: error))
        }
    }

    func setPaused(_ paused: Bool) async {
        guard paused != isPaused else { return }
        isPaused = paused
        defaults.set(paused, forKey: DefaultsKeys.isDiscoveryPaused)
        diagnostics.pauseToggles += 1
        recordEvent(paused ? "Discovery paused." : "Discovery resumed.")

        if paused {
            await stopAdvertising()
        } else {
            await start()
        }
    }

    func stop() async {
        recordEvent("Stopping advertiser.")
        await stopAdvertising()
        healthTask?.cancel()
        healthTask = nil
        ollamaIsReachable = false
        diagnostics.healthTaskStops += 1
    }

    private func stopAdvertising() async {
        acceptTask?.cancel()
        acceptTask = nil
        for tasks in connectionTasks.values { tasks.forEach { $0.cancel() } }
        connectionTasks.removeAll()
        await loomContext.stop()
        mpcAdvertiser.stop()
        isAdvertising = false
        connectedPeerName = nil
        diagnostics.stopCalls += 1
        recordEvent("Advertising stopped.")
    }

    func restartAfterWake() async {
        recordEvent("Mac woke from sleep — restarting advertiser.")
        await stopAdvertising()
        guard !isPaused else { return }
        await start()
    }

    private func acceptMPCChannel(_ channel: PeerChannelAdapter) {
        connectedPeerName = channel.peerName
        diagnostics.incomingConnections += 1
        recordEvent("Accepted MPC connection from \(channel.peerName).")
        Task { [weak self] in
            await self?.serveChannel(channel)
        }
    }

    /// Serves a connected channel (Loom or MPC) by running the proxy and monitoring events.
    private func serveChannel(_ channel: PeerChannelAdapter) async {
        let channelID = channel.id
        let peerName = channel.peerName

        let eventTask = Task { [weak self] in
            for await event in channel.events {
                if case .disconnected = event {
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.connectionTasks.removeValue(forKey: channelID)
                        if self.connectedPeerName == peerName {
                            self.connectedPeerName = nil
                        }
                        self.diagnostics.disconnections += 1
                        self.recordEvent("Connection to \(peerName) disconnected.")
                    }
                    return
                }
            }
        }

        let proxyTask = Task { [weak self] in
            guard let self else { return }
            await self.proxy.handle(channel: channel)
        }

        connectionTasks[channelID] = [eventTask, proxyTask]
    }

    private func startHealthChecks() {
        healthTask?.cancel()
        healthTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let reachable = await OllamaAPIClient.shared.isReachable()
                self.diagnostics.healthChecks += 1
                if !reachable && self.ollamaIsReachable {
                    self.diagnostics.unreachableChecks += 1
                }
                if self.ollamaIsReachable != reachable { self.ollamaIsReachable = reachable }

                let snapshot = await self.proxy.diagnosticsSnapshot()
                self.diagnostics.proxy = snapshot
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    func clearDiagnostics() async {
        diagnostics = HelperDiagnostics()
        await proxy.resetDiagnostics()
        recordEvent("Helper diagnostics reset.")
    }

    private func recordEvent(
        _ message: String,
        level: HelperDiagnosticLevel = .info
    ) {
        let limit = 40
        if diagnostics.recentEvents.count >= limit {
            diagnostics.recentEvents.removeFirst()
        }
        diagnostics.recentEvents.append(
            HelperDiagnosticEvent(
                timestamp: Date(),
                level: level,
                message: message
            )
        )

        if level == .error {
            diagnostics.lastError = message
        }
    }

    private func recordError(_ message: String) {
        recordEvent(message, level: .error)
    }

    private func userFacingStartErrorMessage(for error: Error) -> String {
        let rawMessage = String(describing: error)
        let localizedMessage = error.localizedDescription
        let combined = "\(rawMessage) \(localizedMessage)"

        // errSecMissingEntitlement (-34018): app lacks the keychain-access-groups entitlement.
        // This happens in debug builds that haven't been signed with a real Apple Team.
        let errSecMissingEntitlement = "-34018"
        if combined.contains(errSecMissingEntitlement) {
            return "Failed to start advertiser: Keychain permission is missing for this debug build. In Xcode, open target PastureHelper -> Signing & Capabilities, select your Apple Team, then run again."
        }

        return "Failed to start advertiser: \(localizedMessage)"
    }
}

enum HelperDiagnosticLevel: String, Codable, Sendable {
    case info
    case warning
    case error
}

struct HelperDiagnosticEvent: Identifiable, Equatable, Sendable {
    let id = UUID()
    let timestamp: Date
    let level: HelperDiagnosticLevel
    let message: String
}

struct HelperDiagnostics: Equatable, Sendable {
    var startAttempts = 0
    var startSuccesses = 0
    var startFailures = 0
    var stopCalls = 0
    var pauseToggles = 0
    var incomingConnections = 0
    var disconnections = 0
    var healthChecks = 0
    var unreachableChecks = 0
    var healthTaskStops = 0
    var lastError: String?
    var proxy: ProxyDiagnosticsSnapshot = .init()
    var recentEvents: [HelperDiagnosticEvent] = []
}
