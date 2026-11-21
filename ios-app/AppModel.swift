import Foundation
import SwiftUI

/// Owns the pairing state, the app list, and the HUD settings.
@MainActor
final class AppModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case working(String)
        case ready
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var apps: [InstalledApp] = []
    @Published var gateway: String = "10.7.0.1"

    /// Everything the Metal HUD understands, in one value. Editing any field
    /// re-derives the launch environment below.
    @Published var hud = HUDConfiguration()

    /// Launch behaviour, not injection.
    @Published var killExisting: Bool = true

    /// Filter the list down to apps that look like games.
    @Published var gamesOnly: Bool = false {
        didSet { if oldValue != gamesOnly { gamesFilterChanged() } }
    }
    @Published var lastMessage: String?
    @Published var lastScreenshot: URL?

    /// Live view of the loopback VPN. Refreshed on launch, on return to the
    /// foreground, and by the "check again" button.
    @Published private(set) var vpn = NetworkStatus.VPNState.disconnected
    @Published private(set) var vpnCheckInFlight = false

    /// LocalDevVPN's own URL scheme, declared in Info.plist so `canOpenURL`
    /// tells the truth instead of always returning false.
    private static let vpnScheme = "localdevvpn://"
    /// LocalDevVPN on the App Store. The numeric-only link redirects to the
    /// local storefront, so no country code is baked in.
    static let vpnStoreURL = URL(string: "https://apps.apple.com/app/id6755608044")!

    /// Raw text from the search field. Kept separate from `searchQuery` so that
    /// keystrokes don't drive a full re-filter on every character.
    @Published var searchText: String = "" {
        didSet { searchTextDidChange() }
    }

    /// The debounced query actually used for filtering.
    @Published private(set) var searchQuery: String = ""
    /// Filtered results, recomputed only when the query or the app list changes.
    @Published private(set) var visibleApps: [InstalledApp] = []

    private let pairing = PairingController.shared
    private var searchIndex = AppSearchIndex(apps: [])
    private var searchDebounce: Task<Void, Never>?
    /// Bumped on every keystroke so a stale debounce task can't publish.
    private var searchGeneration: UInt64 = 0

    // MARK: - Derived state

    var isPaired: Bool { PairingController.hasPairingFile }

    /// Convenience so the model never hard-codes English.
    private func s(_ key: L10n.Key) -> String {
        LanguageStore.shared.string(key)
    }

    /// Fill `%@` / `%d` placeholders left to right.
    ///
    /// `String.replacingOccurrences` would replace *every* occurrence of `%@`
    /// on each call, so a template with three placeholders would end up with
    /// the first argument three times. This walks the template once instead.
    static func fill(_ template: String, _ arguments: String...) -> String {
        var result = ""
        var rest = Substring(template)
        var next = 0

        while next < arguments.count {
            let at = rest.range(of: "%@")
            let digits = rest.range(of: "%d")
            let first: Range<Substring.Index>
            switch (at, digits) {
            case let (a?, d?):
                first = a.lowerBound < d.lowerBound ? a : d
            case let (a?, nil):
                first = a
            case let (nil, d?):
                first = d
            case (nil, nil):
                return result + rest
            }
            result += rest[rest.startIndex..<first.lowerBound]
            result += arguments[next]
            rest = rest[first.upperBound...]
            next += 1
        }
        return result + rest
    }

    var pairingStatus: String {
        if isPaired { return s(.statusPaired) }
        return pairing.running ? pairing.status : s(.statusIdle)
    }

    var filteredApps: [InstalledApp] { visibleApps }

    /// Coalesce keystrokes: only the last edit within the window re-filters.
    private func searchTextDidChange() {
        searchDebounce?.cancel()
        let pending = searchText
        searchGeneration &+= 1
        let generation = searchGeneration

        // An empty field should clear instantly; there is nothing to compute.
        guard !pending.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchDebounce = nil
            applySearch(query: "", immediate: true)
            return
        }

        searchDebounce = Task { [weak self] in
            // 120 ms is short enough to feel live and long enough that a fast
            // typist only pays for one pass instead of one per character.
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, let self else { return }
            // A newer keystroke may have started its own task while this one
            // was sleeping; only the newest generation may publish results.
            guard self.searchGeneration == generation else { return }
            self.applySearch(query: pending, immediate: false)
        }
    }

    private func applySearch(query: String, immediate: Bool) {
        searchQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            visibleApps = applyGameFilter(apps)
            return
        }
        // Runs on the main actor; the index precomputed its keys, so this is a
        // handful of `String.contains` calls per app.
        _ = immediate
        visibleApps = applyGameFilter(searchIndex.filtered(by: trimmed))
    }

    /// Apply the "only games" switch on top of a result set.
    private func applyGameFilter(_ input: [InstalledApp]) -> [InstalledApp] {
        guard gamesOnly else { return input }
        return input.filter { GameClassifier.isGame($0) }
    }

    /// Apply the current text immediately, skipping the debounce. Wired to the
    /// keyboard's Search key so pressing it never feels laggy.
    func commitSearch() {
        searchDebounce?.cancel()
        searchDebounce = nil
        applySearch(query: searchText, immediate: true)
    }

    /// Re-run the filter when the *only games* switch flips.
    func gamesFilterChanged() {
        applySearch(query: searchQuery, immediate: true)
    }

    /// Rebuild the folded index and the visible slice in one go.
    private func rebuildIndex() {
        searchIndex = AppSearchIndex(apps: apps)
        applySearch(query: searchQuery, immediate: true)
    }

    /// Put every knob back to the documented defaults.
    func resetHudDefaults() {
        hud = HUDConfiguration()
        killExisting = true
        gamesOnly = false
        applySearch(query: searchQuery, immediate: true)
    }

    /// Restore only the metric selection, leaving placement alone - this is what
    /// the system panel's "Restore default metrics" button does.
    func resetHudMetrics() {
        hud.customMetrics = []
        hud.layout = MetalHUD.defaultLayout
        hud.showZeroMetrics = false
        hud.showMetricsRange = false
    }

    /// The environment we hand to the target process.
    ///
    /// `HUDConfiguration.environment()` already returns an empty dictionary when
    /// the master switch is off, which is the control-group behaviour.
    var environment: [String: String] {
        hud.environment()
    }

    var environmentSummary: String {
        let env = environment
        if env.isEmpty { return "—" }
        return env
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "  ")
    }

    // MARK: - Lifecycle

    func bootstrap() {
        Bridge.installLogging()
        LogCenter.shared.append("[app] MetalHUD core \(Bridge.version)")
        LogCenter.shared.append("[app] interfaces: \(NetworkStatus.describe())")
        pushHosts()
        refreshVPN()
    }

    /// Feed the Rust side the gateway candidates, most likely first.
    func pushHosts() {
        Bridge.clearRoute()
        let candidates = NetworkStatus.tunnelCandidates(preferred: gateway)
        LogCenter.shared.append("[app] gateway candidates: \(candidates.joined(separator: ", "))")
        Bridge.setHosts(candidates)
    }

    // MARK: - VPN

    /// Re-read the interface table. Cheap (one `getifaddrs` sweep) but it does
    /// touch the network stack, so it runs off the main actor.
    ///
    /// This is a *report*, not a reconfiguration. An earlier version rewrote
    /// `gateway` from the detected interface address, which put a wrong guess
    /// (`10.7.1.2`) ahead of the working default and cost 800 ms of connect
    /// timeout per dead candidate on every dial. Detection must never change
    /// the dialling order; the user's gateway field stays authoritative.
    func refreshVPN() {
        guard !vpnCheckInFlight else { return }
        vpnCheckInFlight = true
        Task {
            let state = await Task.detached(priority: .utility) {
                NetworkStatus.vpnState()
            }.value
            vpn = state
            vpnCheckInFlight = false
            LogCenter.shared.append(
                "[app] vpn \(state.isConnected ? "up" : "down")"
                + (state.tunnelAddress.map { " at \($0) (\(state.interfaceName ?? "?"))" } ?? "")
            )
        }
    }

    /// True when LocalDevVPN is installed and can be opened directly.
    var canOpenVPN: Bool {
        guard let url = URL(string: Self.vpnScheme) else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    func openVPN() {
        guard let url = URL(string: Self.vpnScheme) else {
            openVPNStorePage()
            return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
            // The scheme is declared in Info.plist, so a refusal here means the
            // app is gone; fall back to the store instead of doing nothing.
            guard !opened else { return }
            Task { @MainActor in self.openVPNStorePage() }
        }
    }

    func openVPNStorePage() {
        UIApplication.shared.open(Self.vpnStoreURL)
    }

    // MARK: - Pairing

    func startPairing() {
        Task {
            do {
                let path = try await pairing.pair()
                objectWillChange.send()
                LogCenter.shared.append("[app] paired, record at \(path)")
                await refreshApps()
            } catch is CancellationError {
                LogCenter.shared.append("[app] pairing cancelled")
            } catch {
                objectWillChange.send()
                lastMessage = error.localizedDescription
            }
        }
    }

    func cancelPairing() {
        pairing.stop()
    }

    func importPairingFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if PairingController.adoptPairingFile(from: url) {
            LogCenter.shared.append("[app] imported pairing file from \(url.lastPathComponent)")
            objectWillChange.send()
            Task { await refreshApps() }
        } else {
            lastMessage = Self.fill(s(.errUnreadableFile), url.lastPathComponent)
        }
    }

    func forgetPairing() {
        PairingController.deletePairingFile()
        apps = []
        rebuildIndex()
        Bridge.clearRoute()
        objectWillChange.send()
        LogCenter.shared.append("[app] pairing record deleted")
    }

    // MARK: - Device operations

    func refreshApps() async {
        guard isPaired else {
            lastMessage = s(.errPairFirst)
            return
        }
        phase = .working(s(.phaseConnecting))
        pushHosts()

        let path = PairingController.pairingFilePath
        let result = await runOffMain {
            Bridge.listApps(pairingPath: path)
        }

        switch result {
        case .success(let list):
            apps = list
            rebuildIndex()
            phase = .ready
            lastMessage = nil
            LogCenter.shared.append("[app] loaded \(list.count) app(s)")
        case .failure(let error):
            phase = .failed(error.localizedDescription)
            lastMessage = error.localizedDescription
        }
    }

    func probe() {
        guard isPaired else {
            lastMessage = s(.errPairFirst)
            return
        }
        Task {
            phase = .working(s(.phaseProbing))
            pushHosts()
            let path = PairingController.pairingFilePath
            let result = await runOffMain {
                Bridge.probe(pairingPath: path)
            }
            switch result {
            case .success(let probe):
                phase = .ready
                lastMessage = Self.fill(s(.probeReached),
                                        probe.host,
                                        "\(probe.services)",
                                        probe.appService ? "yes" : "no",
                                        probe.dvt ? "yes" : "no")
            case .failure(let error):
                phase = .failed(error.localizedDescription)
                lastMessage = error.localizedDescription
            }
        }
    }

    func launch(_ app: InstalledApp) {
        Task {
            phase = .working(Self.fill(s(.phaseLaunching), app.name))
            pushHosts()

            // Snapshot the value types we need so the detached closure captures
            // no actor-isolated state.
            let env = environment
            let bundle = app.bundleId
            let kill = killExisting
            let path = PairingController.pairingFilePath

            let result = await runOffMain {
                Bridge.launch(
                    pairingPath: path,
                    bundleID: bundle,
                    environment: env,
                    arguments: [],
                    killExisting: kill
                )
            }

            switch result {
            case .success(let message):
                phase = .ready
                lastMessage = message
                LogCenter.shared.append("[app] \(message)")
            case .failure(let error):
                phase = .failed(error.localizedDescription)
                lastMessage = error.localizedDescription
            }
        }
    }

    func captureScreenshot() {
        guard isPaired else {
            lastMessage = s(.errPairFirst)
            return
        }
        Task {
            phase = .working(s(.phaseCapturing))
            pushHosts()

            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let destination = PairingController.documentsDirectory
                .appendingPathComponent("screenshot-\(stamp).png")
            let path = destination.path
            let pairingPath = PairingController.pairingFilePath

            let result = await runOffMain {
                Bridge.screenshot(
                    pairingPath: pairingPath,
                    destination: path
                )
            }

            switch result {
            case .success(let message):
                phase = .ready
                lastScreenshot = destination
                lastMessage = message
            case .failure(let error):
                phase = .failed(error.localizedDescription)
                lastMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Helpers

    /// Every bridge call blocks, so keep it off the main actor entirely.
    private func runOffMain<T>(_ work: @escaping () -> Result<T, BridgeError>) async -> Result<T, BridgeError> {
        await Task.detached(priority: .userInitiated) { work() }.value
    }
}
