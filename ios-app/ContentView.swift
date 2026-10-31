import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var pairing = PairingController.shared
    @ObservedObject private var log = LogCenter.shared
    @ObservedObject private var languages = LanguageStore.shared

    @State private var showingImporter = false

    private func t(_ key: L10n.Key) -> String { languages.string(key) }

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
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(t(.appTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker(selection: $languages.language) {
                            ForEach(L10n.Language.allCases) { lang in
                                Text(lang.nativeName).tag(lang)
                            }
                        } label: {
                            Text("Language")
                        }
                    } label: {
                        Image(systemName: "globe")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.refreshApps() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(!model.isPaired)
                    .accessibilityLabel(t(.refresh))
                }
            }
            .task { model.bootstrap() }
            .alert(item: Binding(
                get: { model.lastMessage.map(Message.init) },
                set: { if $0 == nil { model.lastMessage = nil } }
            )) { message in
                Alert(title: Text(t(.appTitle)),
                      message: Text(message.text),
                      dismissButton: .default(Text(t(.ok))))
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
                    Text(t(.appTitle))
                        .font(.headline)
                    Text(t(.appSubtitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
                Text(model.isPaired ? t(.pairingLoaded) : t(.pairingMissing))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if model.isPaired {
                    GlassActionButton(title: t(.forget), systemImage: "trash") {
                        model.forgetPairing()
                    }
                }
            }

            HStack(spacing: 8) {
                Text(t(.gateway))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("10.7.0.1", text: $model.gateway)
                    .textFieldStyle(.plain)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 9))
                    .onSubmit { model.pushHosts() }
                GlassActionButton(title: t(.apply)) { model.pushHosts() }
            }

            HStack(spacing: 8) {
                GlassActionButton(title: t(.probe),
                                  systemImage: "antenna.radiowaves.left.and.right",
                                  disabled: !model.isPaired) {
                    model.probe()
                }
                GlassActionButton(title: t(.screenshot),
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
            Text(t(.pairTitle))
                .font(.subheadline.weight(.semibold))

            Text(t(.pairExplanation))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let pin = pairing.pin {
                HStack {
                    Text(t(.pin))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(pin)
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .foregroundStyle(Theme.accent)
                        .textSelection(.enabled)
                    Spacer()
                }
                .padding(10)
                .background(Theme.accentWash, in: RoundedRectangle(cornerRadius: 12))
            }

            Text(pairing.status)
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if pairing.running {
                    GlassActionButton(title: t(.cancel)) { model.cancelPairing() }
                } else {
                    GlassActionButton(title: t(.startPairingHost),
                                      systemImage: "bonjour",
                                      prominent: true) {
                        model.startPairing()
                    }
                }

                GlassActionButton(title: t(.importPairingFile),
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

    /// Mirrors the layout of Xcode's Graphics HUD options: a master switch, the
    /// two placement knobs, then an Advanced disclosure for the rest.
    private var hudSettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(t(.hudSection))
                .font(.subheadline.weight(.semibold))

            Toggle(t(.hudEnable), isOn: $model.hudEnabled)
                .font(.subheadline)

            Divider().overlay(Theme.separator)

            LabeledContent {
                TextField("0.35", text: $model.hudScale)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .frame(width: 84)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 8))
            } label: {
                Text(t(.hudScale)).font(.caption)
            }
            .foregroundStyle(.secondary)

            LabeledContent {
                Picker("", selection: $model.hudAlignment) {
                    ForEach(HUDAlignment.allCases) { option in
                        Text(t(option.localizationKey)).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            } label: {
                Text(t(.hudAlignment)).font(.caption)
            }
            .foregroundStyle(.secondary)

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(t(.hudLogEnabled), isOn: $model.hudLogEnabled)
                        .font(.caption)
                    Toggle(t(.terminateExisting), isOn: $model.killExisting)
                        .font(.caption)
                }
                .padding(.top, 8)
            } label: {
                Text(t(.hudAdvanced))
                    .font(.caption.weight(.medium))
            }
            .tint(Theme.accent)

            Text(model.environmentSummary)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                GlassActionButton(title: t(.resetDefaults), systemImage: "arrow.counterclockwise") {
                    model.resetHudDefaults()
                }
                Spacer()
            }
        }
        .glassCard()
    }

    // MARK: - Apps

    private var appsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(t(.installedApps)).font(.subheadline.weight(.semibold))
                Spacer()
                Toggle(t(.showOnlyGames), isOn: $model.gamesOnly)
                    .font(.caption2)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .scaleEffect(0.8)
                Text("\(model.visibleApps.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GlassSearchField(text: $model.searchText,
                             placeholder: t(.searchPlaceholder)) {
                model.commitSearch()
            }

            if model.apps.isEmpty {
                Text(t(.noAppsHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if model.visibleApps.isEmpty {
                Text("\(t(.noMatchPrefix)) “\(model.searchQuery)”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.visibleApps) { app in
                        AppRow(app: app, launchTitle: t(.launch)) {
                            model.launch(app)
                        }
                        Divider().overlay(Theme.separator)
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
                Text(t(.tunnelLog)).font(.subheadline.weight(.semibold))
                Spacer()
                GlassActionButton(title: t(.copy)) {
                    UIPasteboard.general.string = log.lines.joined(separator: "\n")
                }
                GlassActionButton(title: t(.clear)) { log.clear() }
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
    let launchTitle: String
    let onLaunch: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.subheadline).lineLimit(1)
                // Only show the bundle id when the name is not already it -
                // otherwise the row reads as the same string twice.
                if app.bundleId != app.name {
                    Text(app.bundleId)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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
                    .background(Theme.accentWash, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .accessibilityLabel(launchTitle)
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
