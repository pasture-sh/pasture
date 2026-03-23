import Foundation
import MultipeerConnectivity
import PastureShared

/// Advertises the Mac helper via MultipeerConnectivity and accepts incoming
/// connections from the Pasture iOS app. Acts as a parallel transport alongside
/// Loom, providing a fallback when Bonjour is unavailable (offline/no shared Wi-Fi).
@MainActor
final class MPCAdvertiser: NSObject, ObservableObject {
    static let serviceType = "pasture-mpc"

    private let myPeerID: MCPeerID
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var handler: MPCAdvertiserHandler?

    private(set) var channels: [MCPeerID: MPCChannel] = [:]
    var onPeerChannel: ((PeerChannelAdapter) -> Void)?

    override init() {
        myPeerID = MCPeerID(displayName: Host.current().localizedName ?? "Pasture for Mac")
        super.init()
    }

    func start(onPeerChannel: @escaping (PeerChannelAdapter) -> Void) {
        guard advertiser == nil else { return }
        self.onPeerChannel = onPeerChannel

        let h = MPCAdvertiserHandler(owner: self)
        handler = h

        let a = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: Self.serviceType)
        a.delegate = h
        advertiser = a

        let b = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        b.delegate = h
        browser = b

        a.startAdvertisingPeer()
        b.startBrowsingForPeers()
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil
        handler = nil

        for channel in channels.values {
            channel.session.disconnect()
        }
        channels.removeAll()
        onPeerChannel = nil
    }

    // MARK: Callbacks from MPCAdvertiserHandler

    func receivedInvitation(
        from peerID: MCPeerID,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        channels[peerID]?.session.disconnect()
        let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = handler
        channels[peerID] = MPCChannel(session: session, peer: peerID)
        invitationHandler(true, session)
    }

    func foundPeer(_ peerID: MCPeerID) {
        guard let browser, channels[peerID] == nil else { return }
        let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = handler
        channels[peerID] = MPCChannel(session: session, peer: peerID)
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    func lostPeer(_ peerID: MCPeerID) {
        channels.removeValue(forKey: peerID)
    }

    func peerConnected(_ peerID: MCPeerID) {
        guard let channel = channels[peerID] else { return }
        onPeerChannel?(channel.toPeerChannelAdapter())
    }

    func peerDisconnected(_ peerID: MCPeerID) {
        channels[peerID]?.peerStateChanged(.notConnected)
        channels.removeValue(forKey: peerID)
    }

    func receivedData(_ data: Data, from peerID: MCPeerID) {
        channels[peerID]?.didReceive(data: data)
    }
}

/// Wraps an MPC invitation handler closure as @unchecked Sendable so it can be
/// dispatched to @MainActor in Swift 6 strict concurrency.
private struct SendableInvitationHandler: @unchecked Sendable {
    let call: (Bool, MCSession?) -> Void
}

// MARK: - MPCAdvertiserHandler

private final class MPCAdvertiserHandler: NSObject,
    MCNearbyServiceAdvertiserDelegate,
    MCNearbyServiceBrowserDelegate,
    MCSessionDelegate,
    @unchecked Sendable
{
    private weak var owner: MPCAdvertiser?

    init(owner: MPCAdvertiser) {
        self.owner = owner
    }

    // MARK: MCNearbyServiceAdvertiserDelegate

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let wrapped = SendableInvitationHandler(call: invitationHandler)
        Task { @MainActor [weak self, wrapped] in
            self?.owner?.receivedInvitation(from: peerID, invitationHandler: wrapped.call)
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {}

    // MARK: MCNearbyServiceBrowserDelegate

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor [weak self] in self?.owner?.foundPeer(peerID) }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in self?.owner?.lostPeer(peerID) }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {}

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
