import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// System background colors that resolve on both iOS and macOS. Use these instead of
/// `Color(.systemGroupedBackground)` (UIKit-only) anywhere in shared views.
extension Color {
    /// The screen behind everything — grouped-list gray on iOS, window background on Mac.
    static var appGroupedBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    /// A card sitting on `appGroupedBackground`.
    static var appCardBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    /// A well or column inside a card area (kanban columns).
    static var appTertiaryBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .tertiarySystemGroupedBackground)
        #else
        Color(nsColor: .underPageBackgroundColor)
        #endif
    }

    /// Plain primary background.
    static var appBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .textBackgroundColor)
        #endif
    }
}
