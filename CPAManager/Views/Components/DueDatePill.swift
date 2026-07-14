import SwiftUI

/// Shows a due date with color that reflects urgency (overdue = red, today = orange).
struct DueDatePill: View {
    let date: Date
    var isComplete: Bool = false

    private var color: Color {
        if isComplete { return .secondary }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let day = cal.startOfDay(for: date)
        if day < today { return .red }
        if day == today { return .orange }
        return .secondary
    }

    var body: some View {
        Label(Format.relativeDay(date), systemImage: "calendar")
            .font(.caption.weight(.medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(color)
    }
}
