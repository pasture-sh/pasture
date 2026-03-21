import Foundation
import Darwin

/// Detects whether Tailscale is active on this Mac by scanning network interfaces
/// for an IPv4 address in the Tailscale CGNAT range (100.64.0.0/10).
@MainActor
final class TailscaleMonitor: ObservableObject {
    @Published private(set) var tailscaleIP: String?

    var isActive: Bool { tailscaleIP != nil }

    init() {
        refresh()
    }

    func refresh() {
        tailscaleIP = Self.detectTailscaleIP()
    }

    private static func detectTailscaleIP() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let head = ifaddr else { return nil }
        defer { freeifaddrs(head) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = head
        while let ptr = cursor {
            let addr = ptr.pointee.ifa_addr
            if let addr, addr.pointee.sa_family == UInt8(AF_INET) {
                var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                               &buf, socklen_t(buf.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(decoding: buf.prefix(while: { $0 != 0 }).map(UInt8.init), as: UTF8.self)
                    if isTailscaleAddress(ip) { return ip }
                }
            }
            cursor = ptr.pointee.ifa_next
        }
        return nil
    }

    /// Tailscale allocates addresses in 100.64.0.0/10 (second octet 64–127).
    private static func isTailscaleAddress(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts[0] == 100 else { return false }
        return (64...127).contains(parts[1])
    }
}
