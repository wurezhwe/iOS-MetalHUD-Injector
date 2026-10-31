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
    @Published var hudScale: String = "0.35"
    @Published var hudAlignment: String = "top-right"
    @Published var hudLogEnabled: Bool = false
    @Published var killExisting: Bool = true
    @Published var lastMessage: String?
    @Published var lastScreenshot: URL?

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

    var pairingStatus: String {
        if isPaired { return "Paired" }
        return pairing.running ? pairing.status : "Not paired yet"
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
            visibleApps = apps
            return
        }
        // Runs on the main actor; the index precomputed its keys, so this is a
        // handful of `String.contains` calls per app.
        _ = immediate
        visibleApps = searchIndex.filtered(by: trimmed)
    }

    /// Apply the current text immediately, skipping the debounce. Wired to the
    /// keyboard's Search key so pressing it never feels laggy.
    func commitSearch() {
        searchDebounce?.cancel()
        searchDebounce = nil
        applySearch(query: searchText, immediate: true)
    }

    /// Rebuild the folded index and the visible slice in one go.
    private func rebuildIndex() {
        searchIndex = AppSearchIndex(apps: apps)
        applySearch(query: searchQuery, immediate: true)
    }

    /// The environment we hand to the target process.
    var environment: [String: String] {
        var env = ["MTL_HUD_ENABLED": "1"]
        let scale = hudScale.trimmingCharacters(in: .whitespacesAndNewlines)
        if !scale.isEmpty { env["MTL_HUD_SCALE"] = scale }
        let alignment = hudAlignment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !alignment.isEmpty { env["MTL_HUD_ALIGNMENT"] = alignment }
        if hudLogEnabled { env["MTL_HUD_LOG_ENABLED"] = "1" }
        return env
    }

    var environmentSummary: String {
        environment
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
    }

    /// Feed the Rust side the gateway candidates, most likely first.
    func pushHosts() {
        Bridge.clearRoute()
        let candidates = NetworkStatus.tunnelCandidates(preferred: gateway)
        LogCenter.shared.append("[app] gateway candidates: \(candidates.joined(separator: ", "))")
        Bridge.setHosts(candidates)
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
            lastMessage = "Could not read \(url.lastPathComponent)."
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
            lastMessage = "Pair with this device first."
            return
        }
        phase = .working("Connecting to the device…")
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
            lastMessage = "Pair with this device first."
            return
        }
        Task {
            phase = .working("Probing the device…")
            pushHosts()
            let path = PairingController.pairingFilePath
            let result = await runOffMain {
                Bridge.probe(pairingPath: path)
            }
            switch result {
            case .success(let probe):
                phase = .ready
                lastMessage = "Reached the device at \(probe.host) · \(probe.services) services · "
                    + "appservice=\(probe.appService ? "yes" : "no") · dvt=\(probe.dvt ? "yes" : "no")"
            case .failure(let error):
                phase = .failed(error.localizedDescription)
                lastMessage = error.localizedDescription
            }
        }
    }

    func launch(_ app: InstalledApp) {
        Task {
            phase = .working("Launching \(app.name)…")
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
            lastMessage = "Pair with this device first."
            return
        }
        Task {
            phase = .working("Capturing the screen…")
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
