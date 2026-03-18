import Foundation
import LoomKit

/// Manages the LoomKit context that advertises this Mac on the local network
/// and accepts incoming connections from the Pasture iOS app.
@MainActor
final class LoomAdvertiser: ObservableObject {
    @Published private(set) var connectedPeerName: String?
    @Published private(set) var isAdvertising = false
    @Published private(set) var isPaused = false
    @Published private(set) var ollamaIsReachable = false
    @Published private(set) var diagnostics = HelperDiagnostics()

    private let loomContext: LoomContext
    private let proxy: OllamaProxy
    private var acceptTask: Task<Void, Never>?
    private var healthTask: Task<Void, Never>?
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

        do {
            try await loomContext.start()
            isAdvertising = true
            diagnostics.startSuccesses += 1
            recordEvent("Advertising started.")

            acceptTask = Task { [weak self] in
                guard let self else { return }

                for await connection in self.loomContext.incomingConnections {
                    let peerName = await connection.peer.name

                    await MainActor.run {
                        self.connectedPeerName = peerName
                        self.diagnostics.incomingConnections += 1
                        self.recordEvent("Accepted connection from \(peerName).")
                    }

                    Task { [weak self] in
                        for await event in connection.events {
                            if case .disconnected = event {
                                await MainActor.run {
                                    guard let self else { return }
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

                    Task {
                        await self.proxy.handle(connection: connection)
                    }
                }
            }
        } catch {
            print("[LoomAdvertiser] Failed to start: \(error)")
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
        await loomContext.stop()
        isAdvertising = false
        connectedPeerName = nil
        diagnostics.stopCalls += 1
        recordEvent("Advertising stopped.")
    }

    private func startHealthChecks() {
        healthTask?.cancel()
        healthTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let reachable = await OllamaAPIClient.shared.isReachable()
                self.ollamaIsReachable = reachable
                self.diagnostics.healthChecks += 1
                if !reachable {
                    self.diagnostics.unreachableChecks += 1
                }

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
        diagnostics.recentEvents.append(
            HelperDiagnosticEvent(
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
        diagnostics.startFailures += 1
        recordEvent(message, level: .error)
    }

    private func userFacingStartErrorMessage(for error: Error) -> String {
        let rawMessage = String(describing: error)
        let localizedMessage = error.localizedDescription
        let combined = "\(rawMessage) \(localizedMessage)"

        if combined.contains("-34018") {
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
