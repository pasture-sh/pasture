import Foundation

public enum PeerChannelEvent: Sendable {
    case disconnected
}

public enum PeerTransportType: Sendable {
    case loom
    case mpc
}

/// Transport-agnostic channel used by ConnectionManager and OllamaProxy.
/// Wraps either a Loom connection handle or an MPC session behind a uniform interface.
/// Create instances via `LoomConnectionHandle.toPeerChannelAdapter()` or `MPCChannel.toPeerChannelAdapter()`.
public struct PeerChannelAdapter: Sendable {
    public let id: UUID
    public let peerName: String
    public let transportType: PeerTransportType
    public let messages: AsyncStream<Data>
    public let events: AsyncStream<PeerChannelEvent>

    private let _send: @Sendable (Data) async throws -> Void
    private let _disconnect: @Sendable () async -> Void

    public init(
        id: UUID,
        peerName: String,
        transportType: PeerTransportType,
        messages: AsyncStream<Data>,
        events: AsyncStream<PeerChannelEvent>,
        send: @escaping @Sendable (Data) async throws -> Void,
        disconnect: @escaping @Sendable () async -> Void
    ) {
        self.id = id
        self.peerName = peerName
        self.transportType = transportType
        self.messages = messages
        self.events = events
        self._send = send
        self._disconnect = disconnect
    }

    public func send(_ data: Data) async throws {
        try await _send(data)
    }

    public func disconnect() async {
        await _disconnect()
    }
}

public extension PeerChannelAdapter {
    /// Encodes `message` as JSON and sends it. Convenience over `send(_ data:)`.
    func send<T: Encodable>(_ message: T) async throws {
        let data = try JSONEncoder().encode(message)
        try await send(data)
    }
}
