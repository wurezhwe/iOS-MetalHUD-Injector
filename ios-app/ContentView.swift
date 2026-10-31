import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var pairing = PairingController.shared
    @ObservedObject private var log = LogCenter.shared

    @State private var showingImporter = false
    @State private var showingConsole = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                }
                // Dismiss the keyboard when the list is dragged, which is what
                // makes the search field stop stealing taps while scrolling.
                .scrollDismissesKeyboard(.interactively)
            }
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
        VStack(alignment: .leading, spacing: 10) {
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
        .glassCard()
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
                    GlassActionButton(title: "Forget", systemImage: "trash") {
                        model.forgetPairing()
                    }
                }
            }

            HStack(spacing: 8) {
                Text("Gateway").font(.caption).foregroundStyle(.secondary)
                TextField("10.7.0.1", text: $model.gateway)
                    .textFieldStyle(.plain)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                    .onSubmit { model.pushHosts() }
                GlassActionButton(title: "Apply") { model.pushHosts() }
            }

            HStack(spacing: 8) {
                GlassActionButton(title: "Probe",
                                  systemImage: "antenna.radiowaves.left.and.right",
                                  disabled: !model.isPaired) {
                    model.probe()
                }
                GlassActionButton(title: "Screenshot",
                                  systemImage: "camera",
                                  disabled: !model.isPaired) {
                    model.captureScreenshot()
                }
            }
        }
        .glassCard()
    }

    // MARK: - Pairing

    private var pairingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pair this device")
                .font(.subheadline.weight(.semibold))

            Text("iOS 27 can pair with a host running inside an app. Start the host, then approve the 6-digit PIN in Settings › Privacy & Security › Developer Mode › Pair with MetalHUD.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let pin = pairing.pin {
                HStack {
                    Text("PIN").font(.caption).foregroundStyle(.secondary)
                    Text(pin)
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .foregroundStyle(Theme.accent)
                        .textSelection(.enabled)
                    Spacer()
                }
                .padding(10)
                .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
            }

            Text(pairing.status)
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if pairing.running {
                    GlassActionButton(title: "Cancel") { model.cancelPairing() }
                } else {
                    GlassActionButton(title: "Start pairing host",
                                      systemImage: "bonjour",
                                      prominent: true) {
                        model.startPairing()
                    }
                }

                GlassActionButton(title: "Import pairing file",
                                  systemImage: "square.and.arrow.down") {
                    showingImporter = true
                }
            }
        }
        .glassCard()
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

            HStack(spacing: 10) {
                Text("Scale").font(.caption).foregroundStyle(.secondary)
                TextField("0.35", text: $model.hudScale)
                    .textFieldStyle(.plain)
                    .keyboardType(.decimalPad)
                    .frame(maxWidth: 80)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))

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
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    // MARK: - Apps

    private var appsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Installed apps").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(model.visibleApps.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GlassSearchField(text: $model.searchText,
                             placeholder: "搜索应用 / name / bundle id") {
                model.commitSearch()
            }

            if model.apps.isEmpty {
                Text("Tap the refresh button to load the app list over the tunnel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if model.visibleApps.isEmpty {
                Text("No app matches “\(model.searchQuery)”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Lazy so a long list doesn't build hundreds of rows at once;
                // the previous plain ForEach rebuilt every row on each keystroke.
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.visibleApps) { app in
                        AppRow(app: app) { model.launch(app) }
                        Divider().opacity(0.18)
                    }
                }
            }
        }
        .glassCard()
    }

    // MARK: - Console

    private var consoleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tunnel log").font(.subheadline.weight(.semibold))
                Spacer()
                GlassActionButton(title: "Copy") {
                    UIPasteboard.general.string = log.lines.joined(separator: "\n")
                }
                GlassActionButton(title: "Clear") { log.clear() }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(log.lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(line.contains("failed") || line.contains("error")
                                             ? Theme.warn : Color.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(height: 190)
        }
        .glassCard()
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
            Spacer(minLength: 8)
            if !app.version.isEmpty {
                Text("v\(app.version)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button(action: onLaunch) {
                Image(systemName: "play.fill")
                    .font(.caption.weight(.bold))
                    .frame(width: 30, height: 30)
                    .background(Theme.accent.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private struct Message: Identifiable {
    let text: String
    var id: String { text }

    init(_ text: String) { self.text = text }
}

enum Theme {
    static let background = LinearGradient(
        colors: [Color(red: 0.04, green: 0.05, blue: 0.08),
                 Color(red: 0.09, green: 0.11, blue: 0.16),
                 Color(red: 0.05, green: 0.06, blue: 0.10)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let accent = Color(red: 0.369, green: 0.886, blue: 1.0)
    static let good = Color(red: 0.42, green: 0.86, blue: 0.55)
    static let warn = Color(red: 1.0, green: 0.69, blue: 0.32)
}
