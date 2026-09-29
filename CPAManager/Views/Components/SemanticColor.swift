import SwiftUI

extension Theme {
    /// The single mapping from a semantic state to a color. Never inline colors for a
    /// state at a call site — add a case to `SemanticState` and map it here.
    static func color(_ state: SemanticState) -> Color {
        switch state {
        case .good:    return good
        case .caution: return caution
        case .bad:     return bad
        case .alert:   return alert
        case .info:    return info
        case .neutral: return neutral
        }
    }
}
