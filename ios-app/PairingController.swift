import Foundation
import MetalHUDFFI

/// Runs the RemotePairing host and publishes it over Bonjour so the device can
/// pair with itself from Settings > Privacy & Security > Developer Mode.
@MainActor
final class PairingController: ObservableObject {

    static let shared = PairingController()

    static let hostName = "MetalHUD"
    /// The device shows us as a computer; keep a Mac identifier.
    static let hostModel = "Mac17,7"
    private let bindAddress = "0.0.0.0"

    private var netService: NetService?
    private let localNetwork = LocalNetworkAuthorization()
    private let keepAlive = KeepAlive()

    @Published private(set) var running = false
    @Published private(set) var pin: String?
    @Published private(set) var status: String = "Not paired"

    private nonisolated static let altIRKKey = "metalhud.pairing.hostAltIRK"

    private nonisolated static var storedAltIRK: String {
        get { UserDefaults.standard.string(forKey: altIRKKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: altIRKKey) }
    }

    private var continuation: CheckedContinuation<String, Error>?

    // MARK: - Paths

    /// Directory the pairing file lives in. Exposed through the Files app so a
    /// pairing record exported elsewhere can be dropped in.
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var pairingFileURL: URL {
        documentsDirectory.appendingPathComponent("metalhud_pairing.plist")
    }

    static var pairingFilePath: String {
        pairingFileURL.path
    }

    /// True when a usable pairing record is already on disk.
    static var hasPairingFile: Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: pairingFilePath)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        return size > 0
    }

    /// Mirror a pairing file the user imported from the Files app.
    @discardableResult
    static func adoptPairingFile(from source: URL) -> Bool {
        guard let data = try? Data(contentsOf: source), !data.isEmpty else { return false }
        if source.path == pairingFilePath {
            return true
        }
        do {
            try data.write(to: pairingFileURL, options: .atomic)
            return true
        } catch {
            LogCenter.shared.append("[pair] could not import \(source.lastPathComponent): \(error.localizedDescription)")
            return false
        }
    }

    static func deletePairingFile() {
        try? FileManager.default.removeItem(at: pairingFileURL)
        storedAltIRK = ""
    }

    // MARK: - Pairing

    /// Start the host and wait for the pairing record. Throws on failure.
    func pair() async throws -> String {
        if running {
            stop()
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return try await withCheckedThrowingContinuation { cont in
            continuation = cont
            start()
        }
    }

    func stop() {
        stopAdvertising()
        keepAlive.stopAll()
        running = false
        pin = nil
        resolve(.failure(CancellationError()))
    }

    private func resolve(_ result: Result<String, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(with: result)
    }

    private func start() {
        stopAdvertising()
        keepAlive.stopAll()
        running = true
        pin = nil
        status = "Starting the pairing host…"

        Task {
            _ = await localNetwork.request()
            guard running else { return }

            keepAlive.startAudio()
            status = "Broadcasting — open Settings to pair"
            runHost()
        }
    }

    private func runHost() {
        let name = Self.hostName
        let model = Self.hostModel
        let bind = bindAddress
        let outPath = Self.pairingFilePath
        let altIRK = Self.storedAltIRK

        nonisolated(unsafe) let ctx = UnsafeMutableRawPointer(
            Unmanaged.passRetained(self).toOpaque()
        )

        DispatchQueue.global(qos: .userInitiated).async {
            var result = MhPairResult()
            let rc = bind.withCString { bindC in
                name.withCString { nameC in
                    model.withCString { modelC in
                        outPath.withCString { outC in
                            altIRK.withCString { irkC in
                                mh_pairing_run_host(
                                    bindC, 0, nameC, modelC, outC, irkC,
                                    pairReadyCallback, pairPinCallback, ctx, &result
                                )
                            }
                        }
                    }
                }
            }

            var outcome: Result<(String, String), Error>
            if rc == 0 {
                let issued = Self.copyString(result.host_alt_irk_hex)
                if !issued.isEmpty {
                    Self.storedAltIRK = issued
                }
                let deviceName = Self.copyString(result.device_name)
                let path = Self.copyString(result.pairing_file_path)
                outcome = .success((
                    deviceName.isEmpty ? "this device" : deviceName,
                    path.isEmpty ? outPath : path
                ))
            } else {
                let message = Self.copyString(result.error)
                outcome = .failure(BridgeError.failed(
                    message.isEmpty ? "pairing failed (rc=\(rc))" : message
                ))
            }
            mh_pairing_result_free(&result)

            DispatchQueue.main.async {
                Unmanaged<PairingController>.fromOpaque(ctx).release()
                self.finish(outcome)
            }
        }
    }

    private func finish(_ outcome: Result<(String, String), Error>) {
        stopAdvertising()
        // Stay alive a few seconds so iOS does not suspend us on the way back
        // from Settings.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.keepAlive.stopAll()
        }
        running = false
        pin = nil

        switch outcome {
        case .success(let (deviceName, path)):
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.intValue ?? 0
            if size == 0 {
                status = "Pairing produced an empty file"
                resolve(.failure(BridgeError.failed(
                    "The device paired but the record is empty. Approve the request and try again."
                )))
            } else {
                status = "Paired with \(deviceName)"
                resolve(.success(path))
            }
        case .failure(let error):
            status = "Pairing failed"
            resolve(.failure(error))
        }
    }

    // MARK: - Bonjour

    fileprivate func advertise(serviceID: String, port: Int32, txt: [String: Data]) {
        stopAdvertising()
        let service = NetService(
            domain: "",
            type: "_remotepairing-pairable-host._tcp.",
            name: serviceID,
            port: port
        )
        service.setTXTRecord(NetService.data(fromTXTRecord: txt))
        service.publish()
        netService = service
        status = "Advertising — Settings > Privacy & Security > Developer Mode"
    }

    fileprivate func presentPIN(_ value: String) {
        pin = value
        status = "Enter PIN \(value) in Settings > Developer Mode"
    }

    private func stopAdvertising() {
        netService?.stop()
        netService = nil
    }

    fileprivate nonisolated static func copyString(_ pointer: UnsafeMutablePointer<CChar>?) -> String {
        guard let pointer else { return "" }
        return String(cString: pointer)
    }
}

// MARK: - C callbacks

private let pairReadyCallback: mh_pair_ready_cb = { ctx, serviceID, port, keys, vals, count in
    guard let ctx, let serviceID else { return }
    let controller = Unmanaged<PairingController>.fromOpaque(ctx).takeUnretainedValue()
    let id = String(cString: serviceID)

    var txt: [String: Data] = [:]
    if let keys, let vals {
        for i in 0..<Int(count) {
            guard let key = keys[i], let value = vals[i] else { continue }
            txt[String(cString: key)] = Data(String(cString: value).utf8)
        }
    }

    DispatchQueue.main.async {
        controller.advertise(serviceID: id, port: Int32(port), txt: txt)
    }
}

private let pairPinCallback: mh_pair_pin_cb = { pin, ctx in
    guard let ctx, let pin else { return }
    let controller = Unmanaged<PairingController>.fromOpaque(ctx).takeUnretainedValue()
    let value = String(cString: pin)
    DispatchQueue.main.async {
        controller.presentPIN(value)
    }
}
