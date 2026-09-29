import SwiftUI

/// Shows a due date with urgency: overdue = red + warning icon, today = alert orange.
/// The icon changes with urgency so it never relies on color alone.
struct DueDatePill: View {
    let date: Date
    var isComplete: Bool = false

    private var state: SemanticState {
        if isComplete { return .neutral }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let day = cal.startOfDay(for: date)
        if day < today { return .bad }
        if day == today { return .alert }
        return .neutral
    }

    private var icon: String {
        switch state {
        case .bad:   return "exclamationmark.triangle.fill"
        case .alert: return "sun.max.fill"
        default:     return "calendar"
        }
    }

    var body: some View {
        Label(Format.relativeDay(date), systemImage: icon)
            .font(.caption.weight(.medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(state == .neutral ? AnyShapeStyle(HierarchicalShapeStyle.secondary) : AnyShapeStyle(Theme.color(state)))
    }
}
