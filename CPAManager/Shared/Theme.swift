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
}
