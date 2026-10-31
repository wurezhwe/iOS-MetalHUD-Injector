import Foundation

/// Search over the installed-app list.
///
/// Two things matter here:
///
/// 1. **Cost.** The list can hold hundreds of bundles with long bundle ids.
///    Creating a folded copy of every string on each keystroke is what made
///    typing feel laggy, so each app is folded exactly once, when the list is
///    built, and lookups run against those precomputed keys.
///
/// 2. **Chinese.** Bundle ids are ASCII, but display names are whatever the App
///    Store shipped - very often Chinese ("王者荣耀", "原神"). Users type either
///    the characters, the pinyin ("wangzhe"), or just the initials ("wzry").
///    CFStringTransform gives us the pinyin; the initials come from it too.
struct AppSearchIndex {

    struct Entry {
        let app: InstalledApp
        /// Lowercased display name, for the plain substring match.
        let name: String
        /// Full pinyin of the display name, e.g. "wangzherongyao".
        let pinyin: String
        /// First letter of each pinyin syllable, e.g. "wzry".
        let initials: String
        /// Lowercased bundle id.
        let bundleId: String
    }

    private(set) var entries: [Entry] = []

    init(apps: [InstalledApp]) {
        entries = apps.map { app in
            let folded = Self.fold(app.name)
            return Entry(
                app: app,
                name: folded.name,
                pinyin: folded.pinyin,
                initials: folded.initials,
                bundleId: app.bundleId.lowercased()
            )
        }
    }

    var isEmpty: Bool { entries.isEmpty }

    /// Filter by `query`. An empty query returns everything, in list order.
    func filtered(by query: String) -> [InstalledApp] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return entries.map(\.app) }

        let lowered = needle.lowercased()
        let compact = lowered.replacingOccurrences(of: " ", with: "")

        var out: [InstalledApp] = []
        out.reserveCapacity(entries.count)

        for entry in entries {
            if entry.bundleId.contains(lowered)
                || entry.name.contains(lowered)
                || (!compact.isEmpty && entry.pinyin.contains(compact))
                || (!compact.isEmpty && entry.initials.hasPrefix(compact))
                || (!compact.isEmpty && entry.initials.contains(compact))
            {
                out.append(entry.app)
            }
        }
        return out
    }

    // MARK: - Folding

    /// Lowercase, plus pinyin + initials for CJK text.
    ///
    /// `CFStringTransform` with `kCFStringTransformMandarinLatin` turns Han
    /// characters into accented pinyin ("王" -> "wáng"); stripping the combining
    /// marks leaves "wang". Anything already Latin passes through untouched, so
    /// the same path works for "Genshin Impact".
    static func fold(_ text: String) -> (name: String, pinyin: String, initials: String) {
        let lowered = text.lowercased()
        guard text.unicodeScalars.contains(where: isHan) else {
            // No CJK: pinyin is the plain text, and initials would be noise.
            return (lowered, lowered, "")
        }

        let latin = mandarinLatin(text)
        let syllables = latin
            .split(whereSeparator: { $0 == " " || $0 == "-" })
            .map(String.init)
        let compact = syllables.joined().lowercased()
        let initials = syllables.compactMap { $0.first }.map { String($0).lowercased() }.joined()

        return (lowered, compact, initials)
    }

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF,     // CJK Extension A
             0x4E00...0x9FFF,     // CJK Unified Ideographs
             0xF900...0xFAFF,     // CJK Compatibility Ideographs
             0x20000...0x2FA1F:   // Extensions B-F and supplement
            return true
        default:
            return false
        }
    }

    private static func mandarinLatin(_ text: String) -> String {
        let mutable = NSMutableString(string: text) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        return (mutable as String)
    }
}
