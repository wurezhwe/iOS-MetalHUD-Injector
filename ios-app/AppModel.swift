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
    @Published var searchText: String = ""
    @Published var gateway: String = "10.7.0.1"
    @Published var hudScale: String = "0.35"
    @Published var hudAlignment: String = "top-right"
    @Published var hudLogEnabled: Bool = false
    @Published var killExisting: Bool = true
    @Published var lastMessage: String?
    @Published var lastScreenshot: URL?

    private let pairing = PairingController.shared

    // MARK: - Derived state

    var isPaired: Bool { PairingController.hasPairingFile }

    var pairingStatus: String {
        if isPaired { return "Paired" }
        return pairing.running ? pairing.status : "Not paired yet"
    }

    var filteredApps: [InstalledApp] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(needle)
                || $0.bundleId.localizedCaseInsensitiveContains(needle)
        }
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

        let result = await runOffMain {
            Bridge.listApps(pairingPath: PairingController.pairingFilePath)
        }

        switch result {
        case .success(let list):
            apps = list
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
            let result = await runOffMain {
                Bridge.probe(pairingPath: PairingController.pairingFilePath)
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

            let result = await runOffMain {
                Bridge.launch(
                    pairingPath: PairingController.pairingFilePath,
                    bundleID: app.bundleId,
                    environment: environment,
                    arguments: [],
                    killExisting: killExisting
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

            let result = await runOffMain {
                Bridge.screenshot(
                    pairingPath: PairingController.pairingFilePath,
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
