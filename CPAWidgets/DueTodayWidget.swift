import WidgetKit
import SwiftUI

struct DueTodayEntry: TimelineEntry {
    let date: Date
    let snapshot: DashboardSnapshot
}

struct DueTodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> DueTodayEntry {
        DueTodayEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (DueTodayEntry) -> Void) {
        completion(DueTodayEntry(date: .now, snapshot: DashboardSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DueTodayEntry>) -> Void) {
        let entry = DueTodayEntry(date: .now, snapshot: DashboardSnapshot.load())
        // The app reloads timelines whenever data changes; this is just a fallback.
        let refresh = Calendar.current.date(byAdding: .hour, value: 4, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

struct DueTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DueTodayWidget", provider: DueTodayProvider()) { entry in
            DueTodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Due Today")
        .description("Overdue and upcoming work at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct DueTodayWidgetView: View {
    var entry: DueTodayEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: DashboardSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .systemSmall: smallView
        default:           mediumView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checklist")
                Text("Today").font(.caption.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(Theme.brand)

            Text("\(snapshot.dueTodayCount)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text("due today")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if snapshot.overdueCount > 0 {
                Label("\(snapshot.overdueCount) overdue", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
            } else {
                Label("\(snapshot.openProjectCount) open", systemImage: "tray.full")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checklist").foregroundStyle(Theme.brand)
                Text("Coming Up").font(.subheadline.weight(.semibold))
                Spacer()
                if snapshot.overdueCount > 0 {
                    Text("\(snapshot.overdueCount) overdue")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                }
                Text("\(snapshot.dueTodayCount) today")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            if snapshot.upcoming.isEmpty {
                Spacer()
                Text("All caught up 🎉")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ForEach(snapshot.upcoming.prefix(4)) { item in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(item.isOverdue ? Color.red : Color.secondary.opacity(0.5))
                            .frame(width: 6, height: 6)
                        Text(item.title)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let due = item.dueDate {
                            Text(Format.relativeDay(due))
                                .font(.caption2)
                                .foregroundStyle(item.isOverdue ? .red : .secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
