import MultipeerConnectivity

// MCPeerID is immutable after creation and safe to pass across concurrency domains.
extension MCPeerID: @retroactive @unchecked Sendable {}

// MCSession is thread-safe per Apple docs (callbacks dispatched internally).
extension MCSession: @retroactive @unchecked Sendable {}
