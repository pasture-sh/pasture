import Foundation
import MultipeerConnectivity

/// Bridges an MCSession peer connection into a PeerChannelAdapter.
/// Acts as MCSessionDelegate to route data and state-change callbacks
/// into async streams. Create once per peer; call toPeerChannelAdapter()
/// to get the uniform channel wrapper used by ConnectionManager / OllamaProxy.
public final class MPCChannel: NSObject, @unchecked Sendable {
    public let id = UUID()
    public let peerName: String
    public let messages: AsyncStream<Data>
    public let events: AsyncStream<PeerChannelEvent>

    public let session: MCSession
    public let peer: MCPeerID

    private let messagesContinuation: AsyncStream<Data>.Continuation
    private let eventsContinuation: AsyncStream<PeerChannelEvent>.Continuation
    private var didFinish = false

    public init(session: MCSession, peer: MCPeerID) {
        self.session = session
        self.peer = peer
        self.peerName = peer.displayName

        let (msgStream, msgCont) = AsyncStream.makeStream(of: Data.self)
        self.messages = msgStream
        self.messagesContinuation = msgCont

        let (evtStream, evtCont) = AsyncStream.makeStream(of: PeerChannelEvent.self)
        self.events = evtStream
        self.eventsContinuation = evtCont

        super.init()
    }

    public func toPeerChannelAdapter() -> PeerChannelAdapter {
        PeerChannelAdapter(
            id: id,
            peerName: peerName,
            transportType: .mpc,
            messages: messages,
            events: events,
            send: { [self] data in
                try self.session.send(data, toPeers: [self.peer], with: .reliable)
            },
            disconnect: { [self] in
                self.session.disconnect()
                self.finishStreams()
            }
        )
    }

    // MARK: Called by the owner (MPCBrowser / MPCAdvertiser)

    public func didReceive(data: Data) {
        messagesContinuation.yield(data)
    }

    public func peerStateChanged(_ state: MCSessionState) {
        if state == .notConnected {
            eventsContinuation.yield(.disconnected)
            finishStreams()
        }
    }

    private func finishStreams() {
        guard !didFinish else { return }
        didFinish = true
        messagesContinuation.finish()
        eventsContinuation.finish()
    }
}
