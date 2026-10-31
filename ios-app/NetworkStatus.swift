import Foundation
import Darwin

/// Network interface inspection, used to feed the Rust tunnel code with sensible
/// candidate gateway addresses.
enum NetworkStatus {

    struct Interface {
        let name: String
        let ipv4: String
        let netmask: String?
    }

    static func interfaces() -> [Interface] {
        var result: [Interface] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            guard let addr = cur.pointee.ifa_addr else { continue }
            guard addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            let name = String(cString: cur.pointee.ifa_name)
            guard let ipv4 = numericHost(addr) else { continue }
            result.append(Interface(name: name,
                                    ipv4: ipv4,
                                    netmask: cur.pointee.ifa_netmask.flatMap(numericHost)))
        }
        return result
    }

    private static func numericHost(_ addr: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let len = socklen_t(MemoryLayout<sockaddr_in>.size)
        guard getnameinfo(addr, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
        else { return nil }
        return String(cString: host)
    }

    /// A one-line summary for the status card.
    static func describe() -> String {
        let parts = interfaces().map { "\($0.name)=\($0.ipv4)" }
        return parts.isEmpty ? "no interfaces" : parts.joined(separator: ", ")
    }

    static func isTunnelInterface(_ name: String) -> Bool {
        // iOS VPNs surface as utunN / ipsecN; some VPN apps use tapN.
        name.hasPrefix("utun") || name.hasPrefix("ipsec")
            || name.hasPrefix("tap") || name.hasPrefix("ppp")
    }

    /// Every address worth dialling for the RSD listener, best guess first.
    static func tunnelCandidates(preferred: String) -> [String] {
        var out: [String] = []
        let trimmed = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            out.append(host(trimmed))
        }

        let ifaces = interfaces().filter { !$0.ipv4.hasPrefix("127.") }
        // Tunnel interfaces first: the VPN gateway lives on one of those.
        let ordered = ifaces.filter { isTunnelInterface($0.name) }
            + ifaces.filter { !isTunnelInterface($0.name) }

        for iface in ordered {
            for candidate in addresses(for: iface) where !out.contains(candidate) {
                out.append(candidate)
            }
        }

        // WireGuard/LocalDevVPN conventions, in case the interface is not up yet.
        for fallback in ["10.7.0.1", "10.7.0.2", "10.7.0.3"]
        where !out.contains(fallback) {
            out.append(fallback)
        }
        return out
    }

    /// The gateway of a /24-ish tunnel is usually the first host in the subnet,
    /// and the device itself is often the second. Offer both.
    private static func addresses(for iface: Interface) -> [String] {
        guard let local = ipv4Value(iface.ipv4) else { return [] }
        var out: [String] = []
        if isTunnelInterface(iface.name) {
            let mask = iface.netmask.flatMap(ipv4Value) ?? 0xFFFF_FF00
            let network = local & mask
            out.append(describe(network &+ 1))
            out.append(describe(network &+ 2))
        }
        out.append(iface.ipv4)
        return out
    }

    static func host(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let slash = trimmed.firstIndex(of: "/") else { return trimmed }
        return String(trimmed[..<slash]).trimmingCharacters(in: .whitespaces)
    }

    private static func describe(_ value: UInt32) -> String {
        "\((value >> 24) & 0xFF).\((value >> 16) & 0xFF).\((value >> 8) & 0xFF).\(value & 0xFF)"
    }

    private static func ipv4Value(_ ip: String) -> UInt32? {
        let octets = ip.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return nil }
        var value: UInt32 = 0
        for octet in octets {
            guard let byte = UInt8(octet) else { return nil }
            value = (value << 8) | UInt32(byte)
        }
        return value
    }
}
