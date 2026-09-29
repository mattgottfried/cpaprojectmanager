import SwiftUI

/// Everyday repeating row for Today: status tile, title, context line, due pill.
/// One combined VoiceOver element; status is icon + word, never color alone.
struct TodayRowCard: View {
    let title: String
    let subtitle: String
    let dueDate: Date?
    let section: TodaySection
    var isProject = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var color: Color { Theme.color(section.color) }

    private var statusWord: String {
        switch section {
        case .overdue:  return "Overdue"
        case .today:    return "Due today"
        case .next:     return "Next up"
        case .comingUp: return "Coming up"
        }
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))

        layout {
            tile
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !subtitle.isEmpty {
                    Label(subtitle, systemImage: isProject ? "folder.fill" : "person.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let dueDate {
                    Label(Format.relativeDay(dueDate), systemImage: "calendar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                }
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(isProject ? "Opens the project" : "Swipe for actions")
    }

    private var accessibilityValue: String {
        var parts = [statusWord]
        if let dueDate { parts.append(Format.relativeDay(dueDate)) }
        if !subtitle.isEmpty { parts.append(subtitle) }
        return parts.joined(separator: ", ")
    }

    private var tile: some View {
        Image(systemName: section.systemImage)
            .font(.title3.weight(.bold))
            .foregroundStyle(color)
            .frame(width: 44, height: 44)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }
}
