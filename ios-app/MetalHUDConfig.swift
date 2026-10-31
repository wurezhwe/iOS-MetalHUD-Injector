import Foundation

/// Every documented `MTL_HUD_*` environment variable, transcribed from
/// Apple's `MetalPerformanceHUD(1)` man page (macOS 26 edition).
///
/// That page is the authority for this file: it lists the accepted values and
/// the clamping range for each key, and the same keys also work as entries in a
/// `CAMetalLayer.developerHUDProperties` dictionary.
///
/// Two details worth calling out because they are easy to get wrong:
///
/// * `MTL_HUD_ALIGNMENT` takes **`topright`**, not `top-right`. The short forms
///   (`tr`) are accepted too. Getting this wrong silently falls back to the
///   default, so the HUD just ignores the setting.
/// * `MTL_HUD_SCALE` is a *fraction of the drawable width* clamped to
///   [0.1, 1.0], not a multiplier on some baseline size. `0.35` means 35% of the
///   width.
enum MetalHUD {

    // MARK: - Alignment

    /// The nine positions `MTL_HUD_ALIGNMENT` accepts.
    enum Alignment: String, CaseIterable, Identifiable {
        case topLeft = "topleft"
        case topCenter = "topcenter"
        case topRight = "topright"
        case centerLeft = "centerleft"
        case centered = "centered"
        case centerRight = "centerright"
        case bottomLeft = "bottomleft"
        case bottomCenter = "bottomcenter"
        case bottomRight = "bottomright"

        var id: String { rawValue }

        /// The short form the man page also accepts.
        var shortForm: String {
            switch self {
            case .topLeft: return "tl"
            case .topCenter: return "tc"
            case .topRight: return "tr"
            case .centerLeft: return "cl"
            case .centered: return "c"
            case .centerRight: return "cr"
            case .bottomLeft: return "bl"
            case .bottomCenter: return "bc"
            case .bottomRight: return "br"
            }
        }

        var localizationKey: L10n.Key {
            switch self {
            case .topLeft: return .alignTopLeft
            case .topCenter: return .alignTopCenter
            case .topRight: return .alignTopRight
            case .centerLeft: return .alignCenterLeft
            case .centered: return .alignCenter
            case .centerRight: return .alignCenterRight
            case .bottomLeft: return .alignBottomLeft
            case .bottomCenter: return .alignBottomCenter
            case .bottomRight: return .alignBottomRight
            }
        }
    }

    // MARK: - Named element layouts

    /// Preset bundles accepted by `MTL_HUD_ELEMENTS` (`Lite` is the default).
    enum Layout: String, CaseIterable, Identifiable {
        case lite = "Lite"
        case fps = "FPS"
        case standard = "Default"
        case rich = "Rich"
        case full = "Full"

        var id: String { rawValue }

        var localizationKey: L10n.Key {
            switch self {
            case .lite: return .layoutLite
            case .fps: return .layoutFPS
            case .standard: return .layoutDefault
            case .rich: return .layoutRich
            case .full: return .layoutFull
            }
        }
    }

    // MARK: - Individual metrics

    /// One entry of the `MTL_HUD_ELEMENTS` comma-separated list.
    enum Metric: String, CaseIterable, Identifiable {
        case device
        case layersize
        case layerscale
        case memory
        case thermal
        case fps
        case fpsgraph
        case framenumber
        case gputime
        case presentdelay
        case frameinterval
        case frameintervalgraph
        case frameintervalhistogram
        case metalcpu
        case shaders
        case disk
        case gputimeline
        case toplabeledcommandbuffers
        case toplabeledencoders

        var id: String { rawValue }

        var localizationKey: L10n.Key {
            switch self {
            case .device: return .metricDevice
            case .layersize: return .metricLayerSize
            case .layerscale: return .metricLayerScale
            case .memory: return .metricMemory
            case .thermal: return .metricThermal
            case .fps: return .metricFPS
            case .fpsgraph: return .metricFPSGraph
            case .framenumber: return .metricFrameNumber
            case .gputime: return .metricGPUTime
            case .presentdelay: return .metricPresentDelay
            case .frameinterval: return .metricFrameInterval
            case .frameintervalgraph: return .metricFrameIntervalGraph
            case .frameintervalhistogram: return .metricFrameIntervalHistogram
            case .metalcpu: return .metricMetalCPU
            case .shaders: return .metricShaders
            case .disk: return .metricDisk
            case .gputimeline: return .metricGPUTimeline
            case .toplabeledcommandbuffers: return .metricTopCommandBuffers
            case .toplabeledencoders: return .metricTopEncoders
            }
        }

        /// Metrics that only produce data when encoder GPU timing is on.
        var needsEncoderTiming: Bool {
            switch self {
            case .gputimeline, .toplabeledcommandbuffers, .toplabeledencoders:
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Documented defaults

    // Kept as constants so the UI can show "default" and the reset button has a
    // single source of truth.
    static let defaultScale = 0.2
    static let defaultOpacity = 1.0
    static let defaultAlignment = Alignment.topRight
    static let defaultLayout = Layout.lite
    static let defaultEncoderTimelineFrameCount = 6
    static let defaultEncoderTimelineSwapDelta = 1.0
    static let defaultInsightTimeout = 10.0
    static let defaultInsightReportInterval = 5.0
    static let defaultRusageUpdateInterval = 3.0
    static let defaultMetricTimeout = 1.0
    static let defaultMFXJitterOffsetRange = 5.0

    /// `MTL_HUD_SCALE` is clamped to this range by the runtime.
    static let scaleRange = 0.1...1.0
    /// `MTL_HUD_ENCODER_GPU_TIMELINE_FRAME_COUNT` is clamped to this range.
    static let timelineFrameRange = 1...10
    /// `MTL_HUD_ENCODER_GPU_TIMELINE_SWAP_DELTA` is clamped to this range.
    static let timelineDeltaRange = 0.1...10.0
}

/// All the HUD knobs the app exposes. Serialised into the launch environment by
/// `AppModel.environment`.
struct HUDConfiguration: Equatable {
    var enabled = true
    var opacity = MetalHUD.defaultOpacity
    var scale = MetalHUD.defaultScale
    var alignment = MetalHUD.defaultAlignment
    /// `nil` means "use the named layout in `layout`"; a non-empty set means the
    /// user picked individual metrics and `MTL_HUD_ELEMENTS` lists them.
    var customMetrics: Set<MetalHUD.Metric> = []
    var layout = MetalHUD.defaultLayout
    var positionX: Int? = nil
    var positionY: Int? = nil

    var encoderTiming = false
    var encoderTimelineFrames = MetalHUD.defaultEncoderTimelineFrameCount
    var encoderTimelineSwapDelta = MetalHUD.defaultEncoderTimelineSwapDelta

    var showZeroMetrics = false
    var showMetricsRange = false

    var insightsEnabled = false
    var insightTimeout = MetalHUD.defaultInsightTimeout
    var insightReportInterval = MetalHUD.defaultInsightReportInterval

    var rusageUpdateInterval = MetalHUD.defaultRusageUpdateInterval
    var metricTimeout = MetalHUD.defaultMetricTimeout

    /// Deprecated upstream but still honoured; off by default.
    var consoleLogging = false

    // MARK: - Serialisation

    /// Build the environment dictionary for the launch call.
    ///
    /// Only values that differ from the documented default are emitted, so the
    /// environment stays readable in the log and we never fight the runtime by
    /// pinning something we don't actually care about.
    func environment() -> [String: String] {
        guard enabled else { return [:] }

        var env: [String: String] = ["MTL_HUD_ENABLED": "1"]

        if abs(opacity - MetalHUD.defaultOpacity) > 0.001 {
            env["MTL_HUD_OPACITY"] = format(opacity)
        }

        if abs(scale - MetalHUD.defaultScale) > 0.001 {
            env["MTL_HUD_SCALE"] = format(scale)
        }

        if alignment != MetalHUD.defaultAlignment {
            env["MTL_HUD_ALIGNMENT"] = alignment.rawValue
        }

        // An explicit position overrides the alignment entirely.
        if let x = positionX {
            env["MTL_HUD_POSITION_X"] = String(x)
        }
        if let y = positionY {
            env["MTL_HUD_POSITION_Y"] = String(y)
        }

        if !customMetrics.isEmpty {
            // Stable order so the log line doesn't churn between launches.
            let names = customMetrics
                .sorted { $0.rawValue < $1.rawValue }
                .map(\.rawValue)
            env["MTL_HUD_ELEMENTS"] = names.joined(separator: ",")
        } else if layout != MetalHUD.defaultLayout {
            env["MTL_HUD_ELEMENTS"] = layout.rawValue
        }

        if encoderTiming {
            env["MTL_HUD_ENCODER_TIMING_ENABLED"] = "1"
            if encoderTimelineFrames != MetalHUD.defaultEncoderTimelineFrameCount {
                env["MTL_HUD_ENCODER_GPU_TIMELINE_FRAME_COUNT"] = String(encoderTimelineFrames)
            }
            if abs(encoderTimelineSwapDelta - MetalHUD.defaultEncoderTimelineSwapDelta) > 0.001 {
                env["MTL_HUD_ENCODER_GPU_TIMELINE_SWAP_DELTA"] = format(encoderTimelineSwapDelta)
            }
        }

        if showZeroMetrics {
            env["MTL_HUD_SHOW_ZERO_METRICS"] = "1"
        }
        if showMetricsRange {
            env["MTL_HUD_SHOW_METRICS_RANGE"] = "1"
        }

        if insightsEnabled {
            env["MTL_HUD_INSIGHTS_ENABLED"] = "1"
            if abs(insightTimeout - MetalHUD.defaultInsightTimeout) > 0.001 {
                env["MTL_HUD_INSIGHT_TIMEOUT"] = format(insightTimeout)
            }
            if abs(insightReportInterval - MetalHUD.defaultInsightReportInterval) > 0.001 {
                env["MTL_HUD_INSIGHT_REPORT_INTERVAL"] = format(insightReportInterval)
            }
        }

        if abs(rusageUpdateInterval - MetalHUD.defaultRusageUpdateInterval) > 0.001 {
            env["MTL_HUD_RUSAGE_UPDATE_INTERVAL"] = format(rusageUpdateInterval)
        }
        if abs(metricTimeout - MetalHUD.defaultMetricTimeout) > 0.001 {
            env["MTL_HUD_METRIC_TIMEOUT"] = format(metricTimeout)
        }

        if consoleLogging {
            env["MTL_HUD_LOG_ENABLED"] = "1"
        }

        return env
    }

    /// One-decimal formatting; the runtime parses floats, not pretty strings.
    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
