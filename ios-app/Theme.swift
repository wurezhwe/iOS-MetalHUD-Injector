import SwiftUI

/// Colour palette that responds to the light/dark appearance.
///
/// The previous version hard-coded a near-black gradient and white overlays and
/// forced `.preferredColorScheme(.dark)`, so light mode was unreadable. Every
/// colour is now either a semantic system colour or a dynamic one built with
/// `UIColor { traitCollection in ... }`, which means the glass materials and
/// text keep their contrast when the user switches appearance.
struct Theme {

    // MARK: - Accent

    /// Slightly different in light mode: the cyan used on black is too pale on
    /// a white card, so light mode gets a deeper teal.
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.369, green: 0.886, blue: 1.000, alpha: 1)
            : UIColor(red: 0.055, green: 0.494, blue: 0.678, alpha: 1)
    })

    static let good = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.42, green: 0.86, blue: 0.55, alpha: 1)
            : UIColor(red: 0.13, green: 0.55, blue: 0.28, alpha: 1)
    })

    static let warn = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.69, blue: 0.32, alpha: 1)
            : UIColor(red: 0.72, green: 0.42, blue: 0.00, alpha: 1)
    })

    // MARK: - Surfaces

    /// Page background. Deep indigo at night, a soft blue-grey page in daylight
    /// so the frosted cards have something to sit on.
    static let background = LinearGradient(
        colors: [
            Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1)
                    : UIColor(red: 0.93, green: 0.945, blue: 0.97, alpha: 1)
            }),
            Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0.09, green: 0.11, blue: 0.16, alpha: 1)
                    : UIColor(red: 0.86, green: 0.89, blue: 0.94, alpha: 1)
            }),
            Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 1)
                    : UIColor(red: 0.95, green: 0.955, blue: 0.975, alpha: 1)
            }),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Fill for inline text fields sitting *on* a glass card.
    static let fieldBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.07)
            : UIColor.black.withAlphaComponent(0.05)
    })

    /// Hairline used between rows.
    static let separator = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.10)
            : UIColor.black.withAlphaComponent(0.08)
    })

    /// Tint behind the accent-coloured chips (PIN box, play button).
    static let accentWash = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.369, green: 0.886, blue: 1.0, alpha: 0.14)
            : UIColor(red: 0.055, green: 0.494, blue: 0.678, alpha: 0.12)
    })
}
