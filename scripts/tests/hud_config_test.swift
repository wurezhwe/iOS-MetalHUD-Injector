// Standalone exercise of HUDConfiguration.environment().
//
// The shipping app has no test target (adding one to an unsigned sideload build
// is more trouble than it is worth), so this file is compiled and run by
// `scripts/verify_hud_config.py` with the Swift toolchain on CI. It asserts the
// exact environment each configuration produces against the documented names in
// MetalPerformanceHUD(1).

import Foundation

func check(_ condition: Bool, _ message: String, _ failures: inout [String]) {
    if !condition { failures.append(message) }
}

var failures: [String] = []

// 1. Master switch off injects nothing at all.
var off = HUDConfiguration()
off.enabled = false
check(off.environment().isEmpty, "disabled HUD must produce an empty environment", &failures)

// 2. Defaults produce only MTL_HUD_ENABLED.
var plain = HUDConfiguration()
plain.enabled = true
let base = plain.environment()
check(base == ["MTL_HUD_ENABLED": "1"],
      "defaults must emit only MTL_HUD_ENABLED, got \(base)", &failures)

// 3. Alignment uses the documented bare form, not the hyphenated one.
var aligned = HUDConfiguration()
aligned.alignment = .bottomLeft
let alignedEnv = aligned.environment()
check(alignedEnv["MTL_HUD_ALIGNMENT"] == "bottomleft",
      "MTL_HUD_ALIGNMENT must be 'bottomleft', got \(alignedEnv["MTL_HUD_ALIGNMENT"] ?? "nil")",
      &failures)
check(alignedEnv["MTL_HUD_ALIGNMENT"]?.contains("-") == false,
      "MTL_HUD_ALIGNMENT must not contain a hyphen", &failures)

// 4. Every alignment value is one of the nine documented strings.
let documented = Set([
    "topleft", "topcenter", "topright",
    "centerleft", "centered", "centerright",
    "bottomleft", "bottomcenter", "bottomright",
])
for value in MetalHUD.Alignment.allCases {
    check(documented.contains(value.rawValue),
          "undocumented alignment '\(value.rawValue)'", &failures)
}
check(MetalHUD.Alignment.allCases.count == documented.count,
      "expected \(documented.count) alignments, got \(MetalHUD.Alignment.allCases.count)",
      &failures)

// 5. Scale and opacity only appear when they differ from the defaults,
//    and are formatted as plain decimals.
var tuned = HUDConfiguration()
tuned.scale = 0.35
tuned.opacity = 0.5
let tunedEnv = tuned.environment()
check(tunedEnv["MTL_HUD_SCALE"] == "0.35",
      "expected MTL_HUD_SCALE=0.35, got \(tunedEnv["MTL_HUD_SCALE"] ?? "nil")", &failures)
check(tunedEnv["MTL_HUD_OPACITY"] == "0.50",
      "expected MTL_HUD_OPACITY=0.50, got \(tunedEnv["MTL_HUD_OPACITY"] ?? "nil")", &failures)

// 6. A named layout is emitted as-is; explicit metrics win over the layout.
var layout = HUDConfiguration()
layout.layout = .rich
check(layout.environment()["MTL_HUD_ELEMENTS"] == "Rich",
      "expected MTL_HUD_ELEMENTS=Rich", &failures)

var metrics = HUDConfiguration()
metrics.layout = .rich
metrics.customMetrics = [.fps, .gputime, .frameintervalhistogram]
let metricValue = metrics.environment()["MTL_HUD_ELEMENTS"] ?? ""
check(metricValue == "fps,frameintervalhistogram,gputime",
      "expected a sorted metric list, got '\(metricValue)'", &failures)

// 7. Every metric name is spelled as documented.
let documentedMetrics = Set([
    "device", "layersize", "layerscale", "memory", "thermal", "fps", "fpsgraph",
    "framenumber", "gputime", "presentdelay", "frameinterval",
    "frameintervalgraph", "frameintervalhistogram", "metalcpu", "shaders",
    "disk", "gputimeline", "toplabeledcommandbuffers", "toplabeledencoders",
])
for metric in MetalHUD.Metric.allCases {
    check(documentedMetrics.contains(metric.rawValue),
          "undocumented metric '\(metric.rawValue)'", &failures)
}

// 8. Encoder timing gates its dependent variables.
var enc = HUDConfiguration()
enc.encoderTiming = false
enc.encoderTimelineFrames = 9
check(enc.environment()["MTL_HUD_ENCODER_GPU_TIMELINE_FRAME_COUNT"] == nil,
      "timeline frames must not be emitted without encoder timing", &failures)

enc.encoderTiming = true
check(enc.environment()["MTL_HUD_ENCODER_TIMING_ENABLED"] == "1",
      "encoder timing flag missing", &failures)
check(enc.environment()["MTL_HUD_ENCODER_GPU_TIMELINE_FRAME_COUNT"] == "9",
      "timeline frame count missing", &failures)

// 9. Absolute position overrides alignment; both may be present in the env.
var positioned = HUDConfiguration()
positioned.positionX = 0
positioned.positionY = 240
let posEnv = positioned.environment()
check(posEnv["MTL_HUD_POSITION_X"] == "0", "positionX missing", &failures)
check(posEnv["MTL_HUD_POSITION_Y"] == "240", "positionY missing", &failures)

// 10. Deprecated console logging is opt-in.
var logging = HUDConfiguration()
check(logging.environment()["MTL_HUD_LOG_ENABLED"] == nil,
      "console logging must be off by default", &failures)
logging.consoleLogging = true
check(logging.environment()["MTL_HUD_LOG_ENABLED"] == "1",
      "console logging flag missing", &failures)

// 11. No key we emit is outside the documented set.
let documentedKeys = Set([
    "MTL_HUD_ENABLED", "MTL_HUD_CONFIG_FILE", "MTL_HUD_OPACITY", "MTL_HUD_SCALE",
    "MTL_HUD_ALIGNMENT", "MTL_HUD_POSITION_X", "MTL_HUD_POSITION_Y",
    "MTL_HUD_ELEMENTS", "MTL_HUD_ENCODER_TIMING_ENABLED",
    "MTL_HUD_ENCODER_GPU_TIMELINE_FRAME_COUNT",
    "MTL_HUD_ENCODER_GPU_TIMELINE_SWAP_DELTA", "MTL_HUD_SHOW_ZERO_METRICS",
    "MTL_HUD_SHOW_METRICS_RANGE", "MTL_HUD_INSIGHTS_ENABLED",
    "MTL_HUD_INSIGHT_TIMEOUT", "MTL_HUD_INSIGHT_REPORT_INTERVAL",
    "MTL_HUD_RUSAGE_UPDATE_INTERVAL", "MTL_HUD_METRIC_TIMEOUT",
    "MTL_HUD_LOG_ENABLED",
])
var everything = HUDConfiguration()
everything.opacity = 0.4
everything.scale = 0.6
everything.alignment = .topCenter
everything.layout = .full
everything.encoderTiming = true
everything.encoderTimelineFrames = 3
everything.encoderTimelineSwapDelta = 2.0
everything.showZeroMetrics = true
everything.showMetricsRange = true
everything.insightsEnabled = true
everything.insightTimeout = 20
everything.insightReportInterval = 8
everything.rusageUpdateInterval = 5
everything.metricTimeout = 2
everything.consoleLogging = true
for key in everything.environment().keys {
    check(documentedKeys.contains(key), "emitted undocumented key '\(key)'", &failures)
}

if failures.isEmpty {
    print("ok: HUD configuration matches MetalPerformanceHUD(1)")
    exit(0)
} else {
    for failure in failures {
        print("FAIL: \(failure)")
    }
    exit(1)
}
