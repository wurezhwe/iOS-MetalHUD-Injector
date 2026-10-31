import Foundation
import MetalHUDFFI

/// Thin Swift wrapper around the Rust `metalhud_ffi` C surface.
///
/// Every call here blocks. The async wrappers hop onto a detached task so the
/// UI keeps running; progress arrives through `LogCenter`.
enum Bridge {

    // MARK: - Lifecycle

    private static var logInstalled = false

    static func installLogging() {
        guard !logInstalled else { return }
        logInstalled = true
        mh_log_init({ _, message in
            guard let message else { return }
            let line = String(cString: message)
            LogCenter.shared.append(line)
        }, nil)
    }

    static var version: String {
        guard let raw = mh_version() else { return "unknown" }
        defer { mh_string_free(raw) }
        return String(cString: raw)
    }

    // MARK: - Hosts

    /// Tell the Rust side which gateway addresses to dial for RSD.
    static func setHosts(_ hosts: [String]) {
        let cleaned = hosts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else {
            mh_set_hosts(nil, 0)
            return
        }
        let cStrings = cleaned.map { strdup($0) }
        defer { cStrings.forEach { free($0) } }
        var pointers: [UnsafePointer<CChar>?] = cStrings.map { UnsafePointer($0) }
        pointers.withUnsafeBufferPointer { buffer in
            mh_set_hosts(buffer.baseAddress, buffer.count)
        }
    }

    static func clearRoute() {
        mh_clear_route()
    }

    // MARK: - Result marshalling

    private static func take(_ pointer: UnsafeMutablePointer<CChar>?) -> String? {
        guard let pointer else { return nil }
        defer { mh_string_free(pointer) }
        let text = String(cString: pointer)
        return text.isEmpty ? nil : text
    }

    private static func callWithStrings(
        _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>,
                 UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32
    ) -> Result<String, BridgeError> {
        var out: UnsafeMutablePointer<CChar>?
        var err: UnsafeMutablePointer<CChar>?
        let rc = body(&out, &err)
        let message = take(out)
        let error = take(err)
        if rc == 0 {
            return .success(message ?? "")
        }
        return .failure(BridgeError.failed(error ?? "unknown error (rc=\(rc))"))
    }

    // MARK: - Operations

    static func listApps(pairingPath: String) -> Result<[InstalledApp], BridgeError> {
        let result = pairingPath.withCString { path in
            callWithStrings { out, err in
                mh_list_apps(path, out, err)
            }
        }
        switch result {
        case .failure(let error):
            return .failure(error)
        case .success(let json):
            guard let data = json.data(using: .utf8) else {
                return .failure(.failed("app list was not valid UTF-8"))
            }
            do {
                let apps = try JSONDecoder().decode([InstalledApp].self, from: data)
                return .success(apps)
            } catch {
                return .failure(.failed("could not decode the app list: \(error.localizedDescription)"))
            }
        }
    }

    static func probe(pairingPath: String) -> Result<DeviceProbe, BridgeError> {
        let result = pairingPath.withCString { path in
            callWithStrings { out, err in
                mh_probe_device(path, out, err)
            }
        }
        switch result {
        case .failure(let error):
            return .failure(error)
        case .success(let json):
            guard let data = json.data(using: .utf8) else {
                return .failure(.failed("probe returned invalid UTF-8"))
            }
            do {
                return .success(try JSONDecoder().decode(DeviceProbe.self, from: data))
            } catch {
                return .failure(.failed("could not decode the probe reply: \(error.localizedDescription)"))
            }
        }
    }

    static func launch(
        pairingPath: String,
        bundleID: String,
        environment: [String: String],
        arguments: [String],
        killExisting: Bool
    ) -> Result<String, BridgeError> {
        let envJSON = encodeJSON(environment) ?? "{}"
        let argsJSON = encodeJSON(arguments) ?? "[]"

        let result = pairingPath.withCString { path in
            bundleID.withCString { bundle in
                envJSON.withCString { env in
                    argsJSON.withCString { args in
                        callWithStrings { out, err in
                            mh_launch_app(path, bundle, env, args, killExisting, out, err)
                        }
                    }
                }
            }
        }
        return result
    }

    static func screenshot(pairingPath: String, destination: String) -> Result<String, BridgeError> {
        let result = pairingPath.withCString { path in
            destination.withCString { dest in
                callWithStrings { out, err in
                    mh_screenshot(path, dest, out, err)
                }
            }
        }
        return result
    }

    private static func encodeJSON<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

enum BridgeError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        }
    }
}

/// One row of the installed-app list, as produced by the Rust side.
struct InstalledApp: Codable, Identifiable, Hashable {
    let bundleId: String
    let name: String
    let version: String
    let developer: Bool

    var id: String { bundleId }

    private enum CodingKeys: String, CodingKey {
        case bundleId, name, version, developer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleId = try container.decode(String.self, forKey: .bundleId)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? bundleId
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? ""
        developer = try container.decodeIfPresent(Bool.self, forKey: .developer) ?? false
    }

    init(bundleId: String, name: String, version: String, developer: Bool) {
        self.bundleId = bundleId
        self.name = name
        self.version = version
        self.developer = developer
    }
}

/// Reply from `mh_probe_device`.
struct DeviceProbe: Codable {
    let host: String
    let services: Int
    let appService: Bool
    let dvt: Bool
}

/// Thread-safe log buffer the Rust callback can append to from any thread.
final class LogCenter: ObservableObject {
    static let shared = LogCenter()

    @Published private(set) var lines: [String] = []

    private let queue = DispatchQueue(label: "metalhud.log")
    private let limit = 600

    func append(_ line: String) {
        queue.async {
            var updated = self.lines
            updated.append(line)
            if updated.count > self.limit {
                updated.removeFirst(updated.count - self.limit)
            }
            DispatchQueue.main.async {
                self.lines = updated
            }
        }
    }

    func clear() {
        DispatchQueue.main.async { self.lines = [] }
    }
}
