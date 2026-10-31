import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var pairing = PairingController.shared
    @ObservedObject private var log = LogCenter.shared

    @State private var showingImporter = false
    @State private var showingConsole = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    connectionCard
                    if model.isPaired {
                        hudSettingsCard
                        appsCard
                    } else {
                        pairingCard
                    }
                    consoleCard
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Metal HUD")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.refreshApps() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(!model.isPaired)
                }
            }
            .task { model.bootstrap() }
            .alert(item: Binding(
                get: { model.lastMessage.map(Message.init) },
                set: { if $0 == nil { model.lastMessage = nil } }
            )) { message in
                Alert(title: Text("Metal HUD"),
                      message: Text(message.text),
                      dismissButton: .default(Text("OK")))
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "speedometer")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Metal Performance HUD")
                        .font(.headline)
                    Text("Launch any App Store app with MTL_HUD_ENABLED injected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if case .working(let what) = model.phase {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(what).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }

    // MARK: - Connection

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: model.isPaired ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(model.isPaired ? Theme.good : Theme.warn)
                Text(model.isPaired ? "Pairing record loaded" : "No pairing record")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if model.isPaired {
                    Button("Forget", role: .destructive) { model.forgetPairing() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            HStack(spacing: 8) {
                Text("Gateway").font(.caption).foregroundStyle(.secondary)
                TextField("10.7.0.1", text: $model.gateway)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .onSubmit { model.pushHosts() }
                Button("Apply") { model.pushHosts() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            HStack(spacing: 8) {
                Button {
                    model.probe()
                } label: {
                    Label("Probe", systemImage: "antenna.radiowaves.left.and.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!model.isPaired)

                Button {
                    model.captureScreenshot()
                } label: {
                    Label("Screenshot", systemImage: "camera")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!model.isPaired)
            }
        }
        .card()
    }

    // MARK: - Pairing

    private var pairingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pair this device")
                .font(.subheadline.weight(.semibold))

            Text("iOS 27 can pair with a host running inside an app. Start the host, then approve the 6-digit PIN in Settings › Privacy & Security › Developer Mode › Pair with MetalHUD.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let pin = pairing.pin {
                HStack {
                    Text("PIN").font(.caption).foregroundStyle(.secondary)
                    Text(pin)
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                }
                .padding(10)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }

            Text(pairing.status)
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if pairing.running {
                    Button("Cancel") { model.cancelPairing() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else {
                    Button {
                        model.startPairing()
                    } label: {
                        Label("Start pairing host", systemImage: "bonjour")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Button {
                    showingImporter = true
                } label: {
                    Label("Import pairing file", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .card()
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.data, .propertyList],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                model.importPairingFile(url)
            }
        }
    }

    // MARK: - HUD settings

    private var hudSettingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Injected environment")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                Text("Scale").font(.caption).foregroundStyle(.secondary)
                TextField("0.35", text: $model.hudScale)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .frame(maxWidth: 90)
                Text("Alignment").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $model.hudAlignment) {
                    ForEach(["top-left", "top-right", "bottom-left", "bottom-right"], id: \.self) {
                        Text($0).tag($0)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Toggle("Also mirror HUD data to the log (MTL_HUD_LOG_ENABLED)", isOn: $model.hudLogEnabled)
                .font(.caption)

            Toggle("Terminate the app if it is already running", isOn: $model.killExisting)
                .font(.caption)

            Text(model.environmentSummary)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .textSelection(.enabled)
        }
        .card()
    }

    // MARK: - Apps

    private var appsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Installed apps").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(model.filteredApps.count)").font(.caption).foregroundStyle(.secondary)
            }

            TextField("Filter by name or bundle id", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()

            if model.apps.isEmpty {
                Text("Tap the refresh button to load the app list over the tunnel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.filteredApps) { app in
                    AppRow(app: app) { model.launch(app) }
                    if app.id != model.filteredApps.last?.id {
                        Divider().opacity(0.25)
                    }
                }
            }
        }
        .card()
    }

    // MARK: - Console

    private var consoleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tunnel log").font(.subheadline.weight(.semibold))
                Spacer()
                Button("Copy") {
                    UIPasteboard.general.string = log.lines.joined(separator: "\n")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                Button("Clear") { log.clear() }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(log.lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(line.contains("failed") || line.contains("error")
                                             ? Theme.warn : Color.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(height: 200)
        }
        .card()
    }
}

// MARK: - Pieces

private struct AppRow: View {
    let app: InstalledApp
    let onLaunch: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.subheadline).lineLimit(1)
                Text(app.bundleId)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if !app.version.isEmpty {
                Text("v\(app.version)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button(action: onLaunch) {
                Image(systemName: "play.fill")
                    .font(.caption.weight(.bold))
                    .padding(8)
                    .background(Theme.accent.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
        }
        .padding(.vertical, 4)
    }
}

private struct Message: Identifiable {
    let text: String
    var id: String { text }

    init(_ text: String) { self.text = text }
}

enum Theme {
    static let background = LinearGradient(
        colors: [Color(red: 0.06, green: 0.07, blue: 0.10),
                 Color(red: 0.11, green: 0.13, blue: 0.18)],
        startPoint: .top,
        endPoint: .bottom
    )
    static let accent = Color(red: 0.369, green: 0.886, blue: 1.0)
    static let good = Color(red: 0.42, green: 0.86, blue: 0.55)
    static let warn = Color(red: 1.0, green: 0.69, blue: 0.32)
}

private extension View {
    func card() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}
