import SwiftUI

/// What a Today row points at; drives its icon and VoiceOver hint.
enum TodayRowKind {
    case task, project, client, invoice, document

    var subtitleIcon: String {
        switch self {
        case .task:    return "person.fill"
        case .project: return "folder.fill"
        case .client:  return "clock.arrow.circlepath"
        case .invoice: return "person.fill"
        case .document: return "person.fill"
        }
    }

    var tileIcon: String? {
        switch self {
        case .client:  return "person.crop.circle.badge.clock"
        case .invoice: return "doc.text.fill"
        case .document: return "doc.badge.clock"
        default:       return nil
        }
    }

    var hint: String {
        switch self {
        case .task:    return "Swipe for actions"
        case .project: return "Opens the project"
        case .client:  return "Opens the client"
        case .invoice: return "Opens the invoice"
        case .document: return "Opens the client"
        }
    }
}

/// Everyday repeating row for Today: status tile, title, context line, due pill.
/// One combined VoiceOver element; status is icon + word, never color alone.
struct TodayRowCard: View {
    let title: String
    let subtitle: String
    let dueDate: Date?
    let section: TodaySection
    var kind: TodayRowKind = .task
    var isRepeating = false

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
                    Label(subtitle, systemImage: kind.subtitleIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    if let dueDate {
                        Label(Format.relativeDay(dueDate), systemImage: "calendar")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(color)
                    }
                    if isRepeating {
                        Label("Repeats", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(kind.hint)
    }

    private var accessibilityValue: String {
        var parts = [statusWord]
        if let dueDate { parts.append(Format.relativeDay(dueDate)) }
        if isRepeating { parts.append("repeats") }
        if !subtitle.isEmpty { parts.append(subtitle) }
        return parts.joined(separator: ", ")
    }

    private var tile: some View {
        Image(systemName: kind.tileIcon ?? section.systemImage)
            .font(.title3.weight(.bold))
            .foregroundStyle(color)
            .frame(width: 44, height: 44)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }
}
