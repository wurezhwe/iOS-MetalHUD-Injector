import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var pairing = PairingController.shared
    @ObservedObject private var log = LogCenter.shared
    @ObservedObject private var languages = LanguageStore.shared

    @State private var showingImporter = false
    /// Disclosure state for the two collapsible HUD sections.
    @State private var showMetrics = false
    @State private var showAdvanced = false

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
        VStack(alignment: .leading, spacing: 0) {
            Text(t(.hudSection))
                .font(.subheadline.weight(.semibold))
                .padding(.bottom, 12)

            // --- master switch -------------------------------------------
            Toggle(isOn: $model.hud.enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t(.hudEnable)).font(.subheadline)
                    if !model.hud.enabled {
                        Text(t(.hudEnableFooter))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.bottom, 10)

            if model.hud.enabled {
                rowDivider

                // --- opacity / scale -------------------------------------
                sliderRow(title: t(.hudOpacity),
                          value: $model.hud.opacity,
                          range: 0...1,
                          format: "%.2f")

                sliderRow(title: t(.hudScale),
                          value: $model.hud.scale,
                          range: MetalHUD.scaleRange,
                          format: "%.2f",
                          footer: t(.hudScaleFooter))

                rowDivider

                // --- position --------------------------------------------
                LabeledContent {
                    Picker("", selection: $model.hud.alignment) {
                        ForEach(MetalHUD.Alignment.allCases) { option in
                            Text(t(option.localizationKey)).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                } label: {
                    Text(t(.hudAlignment)).font(.subheadline)
                }
                .padding(.vertical, 4)

                rowDivider

                // --- metrics layout --------------------------------------
                LabeledContent {
                    Picker("", selection: $model.hud.layout) {
                        ForEach(MetalHUD.Layout.allCases) { layout in
                            Text(t(layout.localizationKey)).tag(layout)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(!model.hud.customMetrics.isEmpty)
                } label: {
                    Text(t(.hudElements)).font(.subheadline)
                }
                .padding(.vertical, 4)

                if !model.hud.customMetrics.isEmpty {
                    Text(t(.hudElementsFooter))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup(isExpanded: $showMetrics) {
                    metricsSelector
                } label: {
                    Text(t(.hudElements))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.accent)
                }
                .tint(Theme.accent)
                .padding(.top, 6)

                HStack {
                    Button(t(.resetMetrics)) { model.resetHudMetrics() }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                    Spacer()
                }
                .padding(.top, 4)

                rowDivider

                // --- advanced --------------------------------------------
                DisclosureGroup(isExpanded: $showAdvanced) {
                    advancedOptions
                } label: {
                    Text(t(.hudAdvanced))
                        .font(.subheadline)
                }
                .tint(Theme.accent)
                .padding(.vertical, 4)
            }

            rowDivider

            // --- launch behaviour (always visible) -----------------------
            Toggle(t(.terminateExisting), isOn: $model.killExisting)
                .font(.caption)
                .padding(.top, 8)

            // --- what will actually be injected --------------------------
            if !model.environmentSummary.isEmpty {
                Text(model.environmentSummary)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }

            HStack {
                GlassActionButton(title: t(.resetDefaults),
                                  systemImage: "arrow.counterclockwise") {
                    model.resetHudDefaults()
                }
                Spacer()
            }
            .padding(.top, 8)
        }
        .glassCard()
    }

    private var rowDivider: some View {
        Divider()
            .overlay(Theme.separator)
            .padding(.vertical, 6)
    }

    /// A label + slider + numeric readout, matching the system panel's rows.
    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String,
        footer: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .tint(Theme.accent)
            if let footer {
                Text(footer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    /// Per-metric toggles. Selecting any of them switches the HUD away from a
    /// named layout onto an explicit `MTL_HUD_ELEMENTS` list.
    private var metricsSelector: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(MetalHUD.Metric.allCases) { metric in
                Toggle(isOn: Binding(
                    get: { model.hud.customMetrics.contains(metric) },
                    set: { isOn in
                        if isOn {
                            model.hud.customMetrics.insert(metric)
                            // Turning on a timeline metric implies the encoder
                            // timing it depends on.
                            if metric.needsEncoderTiming {
                                model.hud.encoderTiming = true
                            }
                        } else {
                            model.hud.customMetrics.remove(metric)
                        }
                    }
                )) {
                    Text(t(metric.localizationKey))
                        .font(.caption)
                }
                .padding(.vertical, 5)
                rowDivider
            }
        }
    }

    private var advancedOptions: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: $model.hud.encoderTiming) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t(.hudEncoderTiming)).font(.caption)
                    Text(t(.hudEncoderTimingFooter))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 6)

            if model.hud.encoderTiming {
                stepperRow(title: t(.hudTimelineFrames),
                           value: $model.hud.encoderTimelineFrames,
                           range: MetalHUD.timelineFrameRange)
                sliderRow(title: t(.hudTimelineDelta),
                          value: $model.hud.encoderTimelineSwapDelta,
                          range: MetalHUD.timelineDeltaRange,
                          format: "%.1f")
            }

            rowDivider

            Toggle(t(.hudShowZero), isOn: $model.hud.showZeroMetrics)
                .font(.caption)
                .padding(.vertical, 6)

            Toggle(t(.hudShowRange), isOn: $model.hud.showMetricsRange)
                .font(.caption)
                .padding(.vertical, 6)

            rowDivider

            Toggle(t(.hudInsights), isOn: $model.hud.insightsEnabled)
                .font(.caption)
                .padding(.vertical, 6)

            if model.hud.insightsEnabled {
                sliderRow(title: t(.hudInsightTimeout),
                          value: $model.hud.insightTimeout,
                          range: 1...60,
                          format: "%.0f")
                sliderRow(title: t(.hudInsightInterval),
                          value: $model.hud.insightReportInterval,
                          range: 1...60,
                          format: "%.0f")
            }

            rowDivider

            Toggle(isOn: $model.hud.consoleLogging) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t(.hudConsoleLogging)).font(.caption)
                    Text(t(.hudConsoleLoggingFooter))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)

            sliderRow(title: t(.hudRusageInterval),
                      value: $model.hud.rusageUpdateInterval,
                      range: 0.1...10,
                      format: "%.1f")

            sliderRow(title: t(.hudMetricTimeout),
                      value: $model.hud.metricTimeout,
                      range: 0.1...5,
                      format: "%.1f")
        }
        .padding(.top, 6)
    }

    private func stepperRow(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        HStack {
            Text(title).font(.caption)
            Spacer()
            Text("\(value.wrappedValue)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Stepper("", value: value, in: range)
                .labelsHidden()
        }
        .padding(.vertical, 4)
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
