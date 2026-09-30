import SwiftUI

/// Status pill (No status / Waiting for client / …), tinted by meaning.
struct TaskStatusChip: View {
    let status: TaskStatus
    var isWaitingOnTask = false

    var body: some View {
        let color = isWaitingOnTask ? Theme.color(.neutral) : Theme.color(status.state)
        Text(isWaitingOnTask ? "Waiting on task" : status.label)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(status == .none || isWaitingOnTask ? Color.secondary : color)
            .background(color.opacity(status == .none || isWaitingOnTask ? 0.08 : 0.15), in: Capsule())
            .overlay { if status == .none && !isWaitingOnTask { Capsule().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 0.5) } }
    }
}

struct TaskPriorityChip: View {
    let priority: Priority

    var body: some View {
        Text(priority.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(priority.color)
            .background(priority.color.opacity(0.15), in: Capsule())
    }
}

/// A due date with an overdue marker: "Sep 30" or "⚠ Sep 28".
struct TaskDueLabel: View {
    let row: TaskTableRow

    var body: some View {
        if let due = row.dueDate {
            HStack(spacing: 4) {
                Text(due.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(row.isOverdue() ? Theme.color(.bad) : Color.primary)
                if row.isOverdue() {
                    Image(systemName: "exclamationmark.circle").font(.caption).foregroundStyle(Theme.color(.caution))
                        .accessibilityLabel("Overdue")
                }
            }
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }
}
