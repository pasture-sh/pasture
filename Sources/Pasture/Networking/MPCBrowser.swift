import Foundation
import MultipeerConnectivity
import PastureShared
import UIKit

/// Discovers nearby macOS Pasture helpers via MultipeerConnectivity.
/// Runs in parallel with Loom discovery; provides an automatic fallback
/// transport when Bonjour/Tailscale is unavailable (e.g. offline, no shared Wi-Fi).
@MainActor
final class MPCBrowser: NSObject, ObservableObject {
    static let serviceType = "pasture-mpc"

    @Published private(set) var discoveredPeers: [MCPeerID] = []

    private let myPeerID: MCPeerID
    private var browser: MCNearbyServiceBrowser?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var handler: MPCBrowserHandler?

    // Active channels keyed by peer. Multiple peers could theoretically connect
    // but in practice Pasture connects to one Mac at a time.
    private(set) var channels: [MCPeerID: MPCChannel] = [:]
    private var pendingInvites: [MCPeerID: CheckedContinuation<PeerChannelAdapter, Error>] = [:]

    override init() {
        myPeerID = MCPeerID(displayName: UIDevice.current.name)
        super.init()
    }

    func start() {
        guard browser == nil else { return }
        let h = MPCBrowserHandler(owner: self)
        handler = h

        let b = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        b.delegate = h
        browser = b

        let a = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: Self.serviceType)
        a.delegate = h
        advertiser = a

        b.startBrowsingForPeers()
        a.startAdvertisingPeer()
    }

    func stop() {
        browser?.stopBrowsingForPeers()
        advertiser?.stopAdvertisingPeer()
        browser = nil
        advertiser = nil
        handler = nil

        for channel in channels.values {
            channel.session.disconnect()
        }
        channels.removeAll()
        discoveredPeers.removeAll()

        for cont in pendingInvites.values {
            cont.resume(throwing: MPCError.stopped)
        }
        pendingInvites.removeAll()
    }

    /// Invites `peer` to a dedicated MCSession and returns a PeerChannelAdapter on success.
    func connect(to peer: MCPeerID) async throws -> PeerChannelAdapter {
        guard let browser else { throw MPCError.notStarted }

        channels[peer]?.session.disconnect()
        let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = handler
        let channel = MPCChannel(session: session, peer: peer)
        channels[peer] = channel

        return try await withCheckedThrowingContinuation { continuation in
            pendingInvites[peer] = continuation
            browser.invitePeer(peer, to: session, withContext: nil, timeout: 10)
        }
    }

    // MARK: Callbacks from MPCBrowserHandler

    func foundPeer(_ peerID: MCPeerID) {
        addDiscoveredPeer(peerID)
    }

    func lostPeer(_ peerID: MCPeerID) {
        discoveredPeers.removeAll { $0 == peerID }
        channels.removeValue(forKey: peerID)
    }

    func peerConnected(_ peerID: MCPeerID) {
        guard let channel = channels[peerID] else { return }
        if let cont = pendingInvites.removeValue(forKey: peerID) {
            cont.resume(returning: channel.toPeerChannelAdapter())
        }
    }

    func peerDisconnected(_ peerID: MCPeerID) {
        channels[peerID]?.peerStateChanged(.notConnected)
        channels.removeValue(forKey: peerID)
        if let cont = pendingInvites.removeValue(forKey: peerID) {
            cont.resume(throwing: MPCError.connectionFailed)
        }
    }

    func receivedData(_ data: Data, from peerID: MCPeerID) {
        channels[peerID]?.didReceive(data: data)
    }

    /// Accept an incoming invitation (Mac invited us, e.g. after Mac became the browser).
    func receivedInvitation(
        from peerID: MCPeerID,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        channels[peerID]?.session.disconnect()
        let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = handler
        channels[peerID] = MPCChannel(session: session, peer: peerID)
        addDiscoveredPeer(peerID)
        invitationHandler(true, session)
    }

    private func addDiscoveredPeer(_ peerID: MCPeerID) {
        if !discoveredPeers.contains(peerID) {
            discoveredPeers.append(peerID)
        }
    }
}

enum MPCError: Error {
    case notStarted
    case connectionFailed
    case stopped
}

/// Wraps an MPC invitation handler closure as @unchecked Sendable so it can be
/// dispatched to @MainActor in Swift 6 strict concurrency.
private struct SendableInvitationHandler: @unchecked Sendable {
    let call: (Bool, MCSession?) -> Void
}

// MARK: - MPCBrowserHandler

private final class MPCBrowserHandler: NSObject,
    MCNearbyServiceBrowserDelegate,
    MCNearbyServiceAdvertiserDelegate,
    MCSessionDelegate,
    @unchecked Sendable
{
    private weak var owner: MPCBrowser?

    init(owner: MPCBrowser) {
        self.owner = owner
    }

    // MARK: MCNearbyServiceBrowserDelegate

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor [weak self] in self?.owner?.foundPeer(peerID) }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in self?.owner?.lostPeer(peerID) }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {}

    // MARK: MCNearbyServiceAdvertiserDelegate

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let wrapped = SendableInvitationHandler(call: invitationHandler)
        Task { @MainActor [weak self, wrapped] in
            self?.owner?.receivedInvitation(from: peerID, invitationHandler: wrapped.call)
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {}

    // MARK: MCSessionDelegate

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor [weak self] in
            switch state {
            case .connected:
                self?.owner?.peerConnected(peerID)
            case .notConnected:
                self?.owner?.peerDisconnected(peerID)
            default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in self?.owner?.receivedData(data, from: peerID) }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
