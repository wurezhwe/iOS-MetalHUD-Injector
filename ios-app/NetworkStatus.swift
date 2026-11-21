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

    // MARK: - VPN state

    /// What the loopback VPN currently looks like from inside the app.
    ///
    /// Deliberately reports and does not infer: the address of the tunnel
    /// interface is the *device's* address on the tunnel, never the gateway
    /// that forwards to RSD. Deriving a gateway from the subnet produced
    /// `10.7.1.1`/`10.7.1.2` for a device on `10.7.1.x`, while the gateway that
    /// actually works is the `10.7.0.1` convention - a different range. So no
    /// gateway is offered here at all.
    struct VPNState {
        /// The address the VPN gave this device, e.g. `10.7.0.2`.
        var tunnelAddress: String?
        var interfaceName: String?
        /// True only when a tunnel interface carries a routable IPv4 address.
        var isConnected: Bool { tunnelAddress != nil }

        static let disconnected = VPNState()
    }

    /// A VPN that is merely *installed* leaves no interface behind; one that is
    /// connected gets a `utunN` with a non-loopback IPv4 address. That is the
    /// only reliable signal available without private APIs, so this is what the
    /// UI reports rather than a guess.
    static func vpnState() -> VPNState {
        let tunnels = interfaces().filter {
            isTunnelInterface($0.name) && !$0.ipv4.hasPrefix("127.")
        }
        // A device may have several utun interfaces (iCloud Private Relay, a
        // personal VPN). Prefer the 10.x one, which is what the loopback VPNs
        // used by sideloading tools allocate.
        let preferred = tunnels.first { $0.ipv4.hasPrefix("10.") } ?? tunnels.first
        guard let iface = preferred else { return .disconnected }

        var state = VPNState()
        state.tunnelAddress = iface.ipv4
        state.interfaceName = iface.name
        return state
    }

    /// Every address worth dialling for the RSD listener, best guess first.
    ///
    /// This list used to be padded with guesses derived from each interface's
    /// subnet (network+1, network+2) plus the device's own addresses. They never
    /// worked: the device sits on e.g. `10.7.1.3` while the gateway that
    /// forwards to RSD is `10.7.0.1`, a different range, and dialling the
    /// device's own LAN address is rejected by pair-verify. Every wrong entry
    /// cost a full connect timeout, so a dial that started on any of them took
    /// seconds. Only the field's value and the known conventions remain; a VPN
    /// with an unusual gateway is one the user types in.
    static func tunnelCandidates(preferred: String) -> [String] {
        var out: [String] = []
        let trimmed = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !out.contains(host(trimmed)) {
            out.append(host(trimmed))
        }

        // WireGuard/LocalDevVPN/StikDebug conventions.
        for fallback in ["10.7.0.1", "10.7.0.2", "10.7.0.3"]
        where !out.contains(fallback) {
            out.append(fallback)
        }
        return out
    }

    static func host(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let slash = trimmed.firstIndex(of: "/") else { return trimmed }
        return String(trimmed[..<slash]).trimmingCharacters(in: .whitespaces)
    }
}
