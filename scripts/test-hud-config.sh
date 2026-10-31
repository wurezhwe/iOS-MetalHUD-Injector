#!/usr/bin/env bash
# Compile and run the HUD configuration test with the CI Swift toolchain.
#
# The app has no XCTest target: it is an unsigned sideload build and adding a
# test bundle only complicates packaging. The pure-logic part of the HUD
# configuration is testable on its own, so it is compiled here against the real
# source file.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"

echo "==> swift version"
swift --version

# MetalHUDConfig.swift references L10n.Key for its localized labels. Stub the
# enum so the file compiles without dragging SwiftUI into a command-line tool.
cat > "$OUT/L10nStub.swift" <<'SWIFT'
enum L10n {
    enum Key: String, CaseIterable {
        case alignTopLeft, alignTopCenter, alignTopRight
        case alignCenterLeft, alignCenter, alignCenterRight
        case alignBottomLeft, alignBottomCenter, alignBottomRight
        case layoutLite, layoutFPS, layoutDefault, layoutRich, layoutFull
        case metricDevice, metricLayerSize, metricLayerScale, metricMemory
        case metricThermal, metricFPS, metricFPSGraph, metricFrameNumber
        case metricGPUTime, metricPresentDelay, metricFrameInterval
        case metricFrameIntervalGraph, metricFrameIntervalHistogram
        case metricMetalCPU, metricShaders, metricDisk, metricGPUTimeline
        case metricTopCommandBuffers, metricTopEncoders
    }
}
SWIFT

echo "==> building the test harness"
swiftc -O \
    "$ROOT/ios-app/MetalHUDConfig.swift" \
    "$OUT/L10nStub.swift" \
    "$ROOT/scripts/tests/hud_config_test.swift" \
    -o "$OUT/hud_config_test"

echo "==> running"
"$OUT/hud_config_test"
