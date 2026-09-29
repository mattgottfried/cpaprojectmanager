import SwiftUI

/// Lightweight palette used across the app and widget. Kept as literal colors (no
/// asset-catalog lookups) so it resolves correctly inside the widget extension too.
enum Theme {
    /// Deep green — evokes ledgers / money, distinct from system blue.
    static let brand = Color(red: 0.106, green: 0.361, blue: 0.616)
    static let brandDark = Color(red: 0.290, green: 0.540, blue: 0.780)

    static func brand(for scheme: ColorScheme) -> Color {
        scheme == .dark ? brandDark : brand
    }

    // MARK: Semantic state colors (see CLAUDE.md → Design). One meaning per color.
    static let good = Color.green
    static let caution = Color(red: 1, green: 0.75, blue: 0)
    static let bad = Color.red
    static let alert = Color(red: 1, green: 0.55, blue: 0)
    static let info = Color.blue
    static let neutral = Color.gray
}
