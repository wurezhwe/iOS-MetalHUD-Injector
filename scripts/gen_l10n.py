"""Generate ios-app/L10n.swift from a single source of truth.

The HUD configuration screen needs ~90 strings in three languages. Keeping the
key enum and the three tables in one Python literal means they cannot drift:
`scripts/gen_l10n.py` writes the Swift file, and `scripts/check_l10n.py` /
`scripts/check_keys.py` verify the result in CI.

Run from the repository root:  python3 scripts/gen_l10n.py
"""
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TARGET = REPO / "ios-app" / "L10n.swift"

# Each row is (key, english, simplified, traditional).
# blank line between groups for readability in the generated file.
GROUPS: list[tuple[str, list[tuple[str, str, str, str]]]] = []


def group(title: str, rows: list[tuple[str, str, str, str]]) -> None:
    GROUPS.append((title, rows))


group("Header", [
    ("appTitle", "Metal HUD", "Metal HUD", "Metal HUD"),
    ("appSubtitle",
     "Launch any App Store app with MTL_HUD_ENABLED injected",
     "给任意 App Store 应用注入 MTL_HUD_ENABLED 后启动",
     "為任意 App Store 應用程式注入 MTL_HUD_ENABLED 後啟動"),
    ("refresh", "Refresh", "刷新", "重新整理"),
    ("language", "Language", "语言", "語言"),
])

group("Connection", [
    ("pairingLoaded", "Pairing record loaded", "已载入配对记录", "已載入配對記錄"),
    ("pairingMissing", "No pairing record", "没有配对记录", "沒有配對記錄"),
    ("forget", "Forget", "删除", "刪除"),
    ("gateway", "Gateway", "网关", "閘道"),
    ("apply", "Apply", "应用", "套用"),
    ("probe", "Probe", "探测", "探測"),
    ("screenshot", "Screenshot", "截图", "截圖"),
])

group("Pairing", [
    ("pairTitle", "Pair this device", "配对本机", "配對本機"),
    ("pairExplanation",
     "iOS 27 can pair with a host running inside an app. Start the host, then "
     "approve the 6-digit PIN in Settings > Privacy & Security > Developer Mode.",
     "iOS 27 起，应用可以作为可配对主机。先启动主机，再进入设置里的开发者模式批准 6 位 PIN。",
     "iOS 27 起，應用程式可以作為可配對主機。先啟動主機，再進入設定裡的開發者模式批准 6 位數 PIN。"),
    ("pin", "PIN", "PIN", "PIN"),
    ("startPairingHost", "Start pairing host", "启动配对主机", "啟動配對主機"),
    ("cancel", "Cancel", "取消", "取消"),
    ("importPairingFile", "Import pairing file", "导入配对文件", "匯入配對檔"),
    ("pairStatusIdle", "Not paired yet", "尚未配对", "尚未配對"),
    ("pairFirst", "Pair with this device first.", "请先配对本机。", "請先配對本機。"),
])

group("HUD basics", [
    ("hudSection", "Metal HUD", "Metal HUD", "Metal HUD"),
    ("hudEnable", "Show Metal Performance HUD",
     "显示 Metal 性能 HUD", "顯示 Metal 效能 HUD"),
    ("hudEnableFooter",
     "Turning this off injects nothing at all, which makes the launch a control "
     "run equivalent to tapping the Home Screen icon.",
     "关闭后不注入任何变量，相当于从桌面图标启动的对照组。",
     "關閉後不注入任何變數，等同從主畫面圖示啟動的對照組。"),
    ("hudOpacity", "Opacity", "不透明度", "不透明度"),
    ("hudScale", "Scale", "缩放比例", "縮放比例"),
    ("hudScaleFooter",
     "Fraction of the drawable width, clamped to 0.1 - 1.0.",
     "占绘制区域宽度的比例，运行时钳制在 0.1 到 1.0。",
     "佔繪製區域寬度的比例，執行時鉗制在 0.1 到 1.0。"),
    ("hudAlignment", "Position", "位置", "位置"),
    ("hudElements", "Metrics", "测量指标", "測量指標"),
    ("hudElementsFooter",
     "Pick a preset layout, or choose individual metrics below.",
     "可以选预设版式，也可以在下面逐个勾选指标。",
     "可以選預設版式，也可以在下面逐項勾選指標。"),
    ("hudAdvanced", "Advanced", "高级", "進階"),
    ("resetDefaults", "Reset to defaults", "还原", "還原"),
    ("resetMetrics", "Restore default metrics", "还原测量指标值", "還原測量指標值"),
    ("hudConsoleLogging", "Log per-frame statistics to the console",
     "把每帧统计写入控制台", "把每幀統計寫入主控台"),
    ("hudConsoleLoggingFooter",
     "Deprecated by Apple. Use metalperftrace instead.",
     "Apple 已弃用，建议改用 metalperftrace。",
     "Apple 已棄用，建議改用 metalperftrace。"),
])

group("HUD advanced", [
    ("hudEncoderTiming", "Encoder GPU time tracking",
     "编码器 GPU 时间跟踪", "編碼器 GPU 時間追蹤"),
    ("hudEncoderTimingFooter",
     "Needed for the GPU timeline and the per-encoder metrics.",
     "GPU 时间线与逐编码器指标需要开启它。",
     "GPU 時間線與逐編碼器指標需要開啟它。"),
    ("hudTimelineFrames", "GPU timeline frames", "GPU 时间线帧数", "GPU 時間線幀數"),
    ("hudTimelineDelta", "GPU timeline interval (s)",
     "GPU 时间线更新间隔（秒）", "GPU 時間線更新間隔（秒）"),
    ("hudShowZero", "Show metrics that are always zero",
     "显示始终为 0 的指标", "顯示始終為 0 的指標"),
    ("hudShowRange", "Show min and max alongside the average",
     "同时显示最小值和最大值", "同時顯示最小值和最大值"),
    ("hudInsights", "Performance insights", "性能分析", "效能分析"),
    ("hudInsightTimeout", "Insight timeout (s)", "提示消失时间（秒）", "提示消失時間（秒）"),
    ("hudInsightInterval", "Insight report interval (s)",
     "提示上报间隔（秒）", "提示上報間隔（秒）"),
    ("hudRusageInterval", "Resource usage refresh (s)",
     "资源占用刷新间隔（秒）", "資源佔用重新整理間隔（秒）"),
    ("hudMetricTimeout", "Transient metric timeout (s)",
     "临时指标超时（秒）", "臨時指標逾時（秒）"),
])

group("HUD launch", [
    ("launchOptions", "Launch options", "启动选项", "啟動選項"),
    ("terminateExisting", "Terminate the app if it is already running",
     "启动前结束已在运行的实例", "啟動前結束已在執行的實例"),
    ("showOnlyGames", "Games only", "只看游戏", "只看遊戲"),
    ("injectedEnvironment", "Injected environment", "注入的环境变量", "注入的環境變數"),
])

group("Layouts", [
    ("layoutLite", "Lite", "精简", "精簡"),
    ("layoutFPS", "FPS only", "仅 FPS", "僅 FPS"),
    ("layoutDefault", "Default", "默认", "預設"),
    ("layoutRich", "Rich", "丰富", "豐富"),
    ("layoutFull", "Full", "完整", "完整"),
])

group("Metrics", [
    ("metricDevice", "Metal device", "Metal 设备", "Metal 裝置"),
    ("metricLayerSize", "Layer size and present mode",
     "层大小和展示模式", "層大小和展示模式"),
    ("metricLayerScale", "Layer scale and pixel format",
     "层缩放与像素格式", "層縮放與像素格式"),
    ("metricMemory", "Memory", "内存", "記憶體"),
    ("metricThermal", "Thermal state", "温度状态", "溫度狀態"),
    ("metricFPS", "FPS", "FPS", "FPS"),
    ("metricFPSGraph", "FPS graph", "FPS 图形", "FPS 圖形"),
    ("metricFrameNumber", "Frame number", "帧编号", "幀編號"),
    ("metricGPUTime", "GPU time", "GPU 时间", "GPU 時間"),
    ("metricPresentDelay", "Present delay", "目前延迟", "目前延遲"),
    ("metricFrameInterval", "Frame interval", "帧间隔", "幀間隔"),
    ("metricFrameIntervalGraph", "Frame interval graph",
     "帧间隔图形", "幀間隔圖形"),
    ("metricFrameIntervalHistogram", "Frame interval histogram",
     "帧间隔直方图", "幀間隔直方圖"),
    ("metricMetalCPU", "Command buffers and encoders",
     "命令缓冲区和编码器计数", "命令緩衝區和編碼器計數"),
    ("metricShaders", "Shader compiler", "着色器编译器", "著色器編譯器"),
    ("metricDisk", "Disk I/O", "磁盘读写", "磁碟讀寫"),
    ("metricGPUTimeline", "Encoder timeline", "编码器时间和 GPU 时间线",
     "編碼器時間和 GPU 時間線"),
    ("metricTopCommandBuffers", "Hottest command buffers",
     "最耗时的命令缓冲区", "最耗時的指令緩衝區"),
    ("metricTopEncoders", "Hottest encoders", "最耗时的编码器", "最耗時的編碼器"),
])

group("Alignment", [
    ("alignTopLeft", "Top left", "左上", "左上"),
    ("alignTopCenter", "Top center", "顶部居中", "頂部置中"),
    ("alignTopRight", "Top right", "右上", "右上"),
    ("alignCenterLeft", "Center left", "左侧居中", "左側置中"),
    ("alignCenter", "Center", "居中", "置中"),
    ("alignCenterRight", "Center right", "右侧居中", "右側置中"),
    ("alignBottomLeft", "Bottom left", "左下", "左下"),
    ("alignBottomCenter", "Bottom center", "底部居中", "底部置中"),
    ("alignBottomRight", "Bottom right", "右下", "右下"),
])

group("Apps", [
    ("installedApps", "Installed apps", "已安装应用", "已安裝應用程式"),
    ("searchPlaceholder", "Search apps, bundle id, or pinyin",
     "搜索应用名、Bundle ID 或拼音", "搜尋名稱、Bundle ID 或拼音"),
    ("noAppsHint", "Tap refresh to load the app list over the tunnel.",
     "点右上角刷新，通过隧道读取应用列表。",
     "點右上角重新整理，透過通道讀取應用程式清單。"),
    ("noMatchPrefix", "No app matches", "没有匹配的应用", "沒有符合的應用程式"),
    ("launch", "Launch", "启动", "啟動"),
    ("tunnelLog", "Tunnel log", "隧道日志", "通道記錄"),
    ("copy", "Copy", "复制", "複製"),
    ("clear", "Clear", "清空", "清除"),
    ("ok", "OK", "好", "好"),
])


def swift_literal(text: str) -> str:
    """Render `text` as a Swift string literal."""
    escaped = text.replace("\\", "\\\\").replace('"', '\\"')
    if len(escaped) <= 72:
        return f'"{escaped}"'
    return f'"""\n        {escaped}\n        """'


HEADER = '''import Foundation
import SwiftUI

/// App-wide localization.
///
/// Generated by `scripts/gen_l10n.py` - edit that file, not this one. Keeping
/// the key enum and all three tables in a single source means they cannot drift;
/// `scripts/check_l10n.py` and `scripts/check_keys.py` verify the result in CI.
enum L10n {

    /// Language the UI is currently rendered in.
    enum Language: String, CaseIterable, Identifiable {
        case english = "en"
        case simplified = "zh-Hans"
        case traditional = "zh-Hant"

        var id: String { rawValue }

        /// Name shown in the picker, always in the language itself.
        var nativeName: String {
            switch self {
            case .english: return "English"
            case .simplified: return "简体中文"
            case .traditional: return "繁體中文"
            }
        }

        var locale: Locale { Locale(identifier: rawValue) }
    }
'''

FOOTER = '''
    // MARK: - Resolution

    /// Translate `key` for `language`, falling back to English and then to the
    /// key itself so a missing entry never traps at runtime.
    static func string(_ key: Key, _ language: Language) -> String {
        let table: [Key: String]
        switch language {
        case .english: table = english
        case .simplified: table = simplified
        case .traditional: table = traditional
        }
        if let value = table[key] { return value }
        if let fallback = english[key] { return fallback }
        return key.rawValue
    }
'''

STORAGE = '''
/// The language currently selected in settings, persisted across launches.
@MainActor
final class LanguageStore: ObservableObject {
    static let shared = LanguageStore()

    private static let defaultsKey = "metalhud.language"

    @Published var language: L10n.Language {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey)
        }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.defaultsKey)
        if let stored, let lang = L10n.Language(rawValue: stored) {
            language = lang
        } else if let preferred = Locale.preferredLanguages.first {
            if preferred.hasPrefix("zh-Hant") || preferred.hasPrefix("zh-TW")
                || preferred.hasPrefix("zh-HK") {
                language = .traditional
            } else if preferred.hasPrefix("zh") {
                language = .simplified
            } else {
                language = .english
            }
        } else {
            language = .english
        }
    }

    func string(_ key: L10n.Key) -> String {
        L10n.string(key, language)
    }
}
'''

TABLE_NAMES = [("english", 1), ("simplified", 2), ("traditional", 3)]


def main() -> None:
    seen: set[str] = set()
    for _, rows in GROUPS:
        for row in rows:
            key = row[0]
            if key in seen:
                raise SystemExit(f"duplicate key: {key}")
            if len(row) != 4:
                raise SystemExit(f"row for {key} must have 4 fields, got {len(row)}")
            seen.add(key)

    parts: list[str] = [HEADER]

    parts.append("\n    /// Every user-visible string.")
    parts.append("    enum Key: String, CaseIterable {")
    for title, rows in GROUPS:
        parts.append(f"        // {title}")
        for row in rows:
            parts.append(f"        case {row[0]}")
    parts.append("    }")
    parts.append(FOOTER)

    for name, column in TABLE_NAMES:
        parts.append(f"\n    private static let {name}: [Key: String] = [")
        for title, rows in GROUPS:
            parts.append(f"        // {title}")
            for row in rows:
                parts.append(f"        .{row[0]}: {swift_literal(row[column])},")
            parts.append("")
        parts.append("    ]")

    # Close L10n *after* the tables, then append the store as a separate type.
    parts.append("}")
    parts.append(STORAGE)

    text = "\n".join(parts)
    TARGET.write_text(text + "\n", encoding="utf-8")
    print(f"wrote {TARGET.relative_to(REPO)} with {len(seen)} keys")


if __name__ == "__main__":
    main()
