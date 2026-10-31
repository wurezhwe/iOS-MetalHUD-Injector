import Foundation

/// Heuristic "is this a game?" used by the *only games* filter.
///
/// App Store metadata is not available over RSD, so this leans on the bundle-id
/// publisher prefixes and display-name keywords that correlate well in practice.
/// It is deliberately labelled as a filter rather than a classification: being
/// wrong only hides a row the user can bring back by turning the switch off.
enum GameClassifier {

    private static let idHints = [
        "mojang", "gameloft", "rockstar", "rockstargames", "epicgames",
        "activision", "ubisoft", "supercell", "roblox", "innersloth", "ustwo",
        "zynga", "devolver", "playdead", "fingersoft", "imangi", "halfbrick",
        "rovio", "mediocre", "noodlecake", "sega", "capcom", "squareenix",
        "bandainamco", "koeitecmo", "cygames", "mihoyo", "hoyoverse",
        "garena", "pubg", "freefire", "riotgames", "blizzard", "bethesda",
        "take2", "nintendo", "pokemon", "niantic", "scopely", "plarium",
        "lilithgame", "archosaur", "hypergryph",
        "tencent.ig", "tencent.tmgp", "tencent.qqgame",
        "netease.mc", "netease.games", "netease.moba", "netease.onmyoji",
        "netease.identity", "pwrd.", "tmgp.", "smoba",
        "minecraft", "roblox",
    ]

    private static let nameHints = [
        "gta", "asphalt", "minecraft", "roblox", "among us", "free fire",
        "pubg", "call of duty", "clash", "brawl", "clans", "warzone",
        "原神", "崩坏", "王者", "和平精英", "使命召唤", "幻塔", "明日方舟",
        "第五人格", "我的世界", "香肠派对", "光遇", "絕區零", "绝区零",
        "遊戲", "游戏",
    ]

    /// Bundle-id suffixes that mark an app extension rather than a launchable
    /// app. These ship inside the parent bundle and would otherwise flood the
    /// list with rows that cannot be launched.
    private static let extensionSuffixes = [
        "Extension", "Widget", "NotificationService", "Broadcast",
        "ShareExtension", "AppExtension", "Intents", "IntentsUI",
    ]

    static func isExtension(_ bundleId: String) -> Bool {
        extensionSuffixes.contains { bundleId.hasSuffix($0) }
    }

    static func isGame(_ app: InstalledApp) -> Bool {
        guard !isExtension(app.bundleId) else { return false }

        let id = app.bundleId.lowercased()
        if idHints.contains(where: { id.contains($0) }) { return true }

        let name = app.name.lowercased()
        return nameHints.contains { name.contains($0.lowercased()) }
    }
}
