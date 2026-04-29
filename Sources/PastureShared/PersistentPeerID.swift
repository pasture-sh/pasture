import Foundation
import MultipeerConnectivity

/// Returns a per-install MCPeerID, archived in UserDefaults so the same identity
/// survives across app launches. MultipeerConnectivity treats freshly created
/// MCPeerIDs as distinct peers even when their display names match, which causes
/// invitations to silently fail after a process restart. Caching the archived
/// instance fixes that. If the device's display name has changed since the cached
/// MCPeerID was created, a new one is generated and re-archived.
public enum PersistentPeerID {
    public static func load(displayName: String, defaultsKey: String) -> MCPeerID {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: defaultsKey),
           let peerID = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: data),
           peerID.displayName == displayName {
            return peerID
        }
        let peerID = MCPeerID(displayName: displayName)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: peerID, requiringSecureCoding: true) {
            defaults.set(data, forKey: defaultsKey)
        }
        return peerID
    }
}
