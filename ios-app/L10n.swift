import Foundation
import SwiftUI

/// App-wide localization.
///
/// Strings live here rather than in `.strings` files so that every key is
/// visible in one place and a missing translation is a compile-time-visible
/// omission instead of a silent fallback to English at runtime.
///
/// The app ships two languages: Simplified Chinese (`zh-Hans`) and English.
/// Traditional Chinese users are served by `zh-Hans` is *not* correct, so
/// `zh-Hant` is included as well and falls back to the same table but with the
/// Traditional glyphs where they differ.
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

    /// Every user-visible string. Grouped by screen so the table stays readable.
    enum Key: String, CaseIterable {
        // Header
        case appTitle
        case appSubtitle
        case refresh
        // Connection
        case pairingLoaded
        case pairingMissing
        case forget
        case gateway
        case apply
        case probe
        case screenshot
        // Pairing
        case pairTitle
        case pairExplanation
        case pin
        case startPairingHost
        case cancel
        case importPairingFile
        case pairStatusIdle
        // HUD settings
        case injectedEnvironment
        case hudSection
        case hudEnable
        case hudScale
        case hudAlignment
        case hudLogEnabled
        case hudAdvanced
        case launchOptions
        case terminateExisting
        case showOnlyGames
        case resetDefaults
        // Apps
        case installedApps
        case searchPlaceholder
        case noAppsHint
        case noMatchPrefix
        case launch
        // Log
        case tunnelLog
        case copy
        case clear
        // Misc
        case ok
        case notPairedYet
        case pairFirst
        // HUD alignment values
        case alignTopLeft
        case alignTopRight
        case alignBottomLeft
        case alignBottomRight
        case alignTopCenter
        case alignBottomCenter
    }

    // MARK: - Resolution

    /// Translate `key` for `language`.
    static func string(_ key: Key, _ language: Language) -> String {
        switch language {
        case .english: return english[key]!
        case .simplified: return simplified[key]!
        case .traditional: return traditional[key]!
        }
    }

    // MARK: - Tables

    private static let english: [Key: String] = [
        .appTitle: "Metal HUD",
        .appSubtitle: "Launch any App Store app with MTL_HUD_ENABLED injected",
        .refresh: "Refresh",

        .pairingLoaded: "Pairing record loaded",
        .pairingMissing: "No pairing record",
        .forget: "Forget",
        .gateway: "Gateway",
        .apply: "Apply",
        .probe: "Probe",
        .screenshot: "Screenshot",

        .pairTitle: "Pair this device",
        .pairExplanation: """
        iOS 27 can pair with a host running inside an app. Start the host, then \
        approve the 6-digit PIN in Settings › Privacy & Security › Developer \
        Mode › Pair with MetalHUD.
        """,
        .pin: "PIN",
        .startPairingHost: "Start pairing host",
        .cancel: "Cancel",
        .importPairingFile: "Import pairing file",
        .pairStatusIdle: "Not paired yet",

        .injectedEnvironment: "Injected environment",
        .hudSection: "Metal HUD",
        .hudEnable: "Enable Metal Performance HUD",
        .hudScale: "Scale",
        .hudAlignment: "Alignment",
        .hudLogEnabled: "Also mirror HUD data to the log",
        .hudAdvanced: "Advanced",
        .launchOptions: "Launch options",
        .terminateExisting: "Terminate the app if it is already running",
        .showOnlyGames: "Show only games",
        .resetDefaults: "Reset to defaults",

        .installedApps: "Installed apps",
        .searchPlaceholder: "Search apps, bundle id, or pinyin",
        .noAppsHint: "Tap refresh to load the app list over the tunnel.",
        .noMatchPrefix: "No app matches",
        .launch: "Launch",

        .tunnelLog: "Tunnel log",
        .copy: "Copy",
        .clear: "Clear",

        .ok: "OK",
        .notPairedYet: "Not paired yet",
        .pairFirst: "Pair with this device first.",

        .alignTopLeft: "Top left",
        .alignTopRight: "Top right",
        .alignBottomLeft: "Bottom left",
        .alignBottomRight: "Bottom right",
        .alignTopCenter: "Top center",
        .alignBottomCenter: "Bottom center",
    ]

    private static let simplified: [Key: String] = [
        .appTitle: "Metal HUD",
        .appSubtitle: "给任意 App Store 应用注入 MTL_HUD_ENABLED 后启动",
        .refresh: "刷新",

        .pairingLoaded: "已载入配对记录",
        .pairingMissing: "没有配对记录",
        .forget: "删除",
        .gateway: "网关",
        .apply: "应用",
        .probe: "探测",
        .screenshot: "截图",

        .pairTitle: "配对本机",
        .pairExplanation: """
        iOS 27 起，应用可以反过来作为“可配对主机”。先启动主机，然后到 \
        设置 › 隐私与安全性 › 开发者模式 › 与 MetalHUD 配对，输入 6 位 PIN。
        """,
        .pin: "PIN",
        .startPairingHost: "启动配对主机",
        .cancel: "取消",
        .importPairingFile: "导入配对文件",
        .pairStatusIdle: "尚未配对",

        .injectedEnvironment: "注入的环境变量",
        .hudSection: "Metal HUD",
        .hudEnable: "显示 Metal 性能 HUD",
        .hudScale: "缩放",
        .hudAlignment: "对齐方式",
        .hudLogEnabled: "同时把 HUD 数据写入日志",
        .hudAdvanced: "高级",
        .launchOptions: "启动选项",
        .terminateExisting: "启动前结束已在运行的实例",
        .showOnlyGames: "只看游戏",
        .resetDefaults: "恢复默认",

        .installedApps: "已安装应用",
        .searchPlaceholder: "搜索应用名、Bundle ID 或拼音",
        .noAppsHint: "点右上角刷新，通过隧道读取应用列表。",
        .noMatchPrefix: "没有匹配的应用",
        .launch: "启动",

        .tunnelLog: "隧道日志",
        .copy: "复制",
        .clear: "清空",

        .ok: "好",
        .notPairedYet: "尚未配对",
        .pairFirst: "请先配对本机。",

        .alignTopLeft: "左上",
        .alignTopRight: "右上",
        .alignBottomLeft: "左下",
        .alignBottomRight: "右下",
        .alignTopCenter: "顶部居中",
        .alignBottomCenter: "底部居中",
    ]

    private static let traditional: [Key: String] = [
        .appTitle: "Metal HUD",
        .appSubtitle: "為任意 App Store 應用程式注入 MTL_HUD_ENABLED 後啟動",
        .refresh: "重新整理",

        .pairingLoaded: "已載入配對記錄",
        .pairingMissing: "沒有配對記錄",
        .forget: "刪除",
        .gateway: "閘道",
        .apply: "套用",
        .probe: "探測",
        .screenshot: "截圖",

        .pairTitle: "配對本機",
        .pairExplanation: """
        iOS 27 起，應用程式可以反過來作為「可配對主機」。先啟動主機，然後到 \
        設定 › 隱私權與安全性 › 開發者模式 › 與 MetalHUD 配對，輸入 6 位數 PIN。
        """,
        .pin: "PIN",
        .startPairingHost: "啟動配對主機",
        .cancel: "取消",
        .importPairingFile: "匯入配對檔",
        .pairStatusIdle: "尚未配對",

        .injectedEnvironment: "注入的環境變數",
        .hudSection: "Metal HUD",
        .hudEnable: "顯示 Metal 效能 HUD",
        .hudScale: "縮放",
        .hudAlignment: "對齊方式",
        .hudLogEnabled: "同時把 HUD 資料寫入記錄",
        .hudAdvanced: "進階",
        .launchOptions: "啟動選項",
        .terminateExisting: "啟動前結束已在執行的實例",
        .showOnlyGames: "只看遊戲",
        .resetDefaults: "回復預設值",

        .installedApps: "已安裝應用程式",
        .searchPlaceholder: "搜尋名稱、Bundle ID 或拼音",
        .noAppsHint: "點右上角重新整理，透過通道讀取應用程式清單。",
        .noMatchPrefix: "沒有符合的應用程式",
        .launch: "啟動",

        .tunnelLog: "通道記錄",
        .copy: "複製",
        .clear: "清除",

        .ok: "好",
        .notPairedYet: "尚未配對",
        .pairFirst: "請先配對本機。",

        .alignTopLeft: "左上",
        .alignTopRight: "右上",
        .alignBottomLeft: "左下",
        .alignBottomRight: "右下",
        .alignTopCenter: "頂部置中",
        .alignBottomCenter: "底部置中",
    ]
}

// MARK: - SwiftUI sugar

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
        // Follow the system language on first launch.
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
