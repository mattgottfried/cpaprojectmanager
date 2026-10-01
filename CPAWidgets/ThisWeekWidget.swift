import WidgetKit
import SwiftUI
import AppIntents

struct ThisWeekEntry: TimelineEntry {
    let date: Date
    let snapshot: DashboardSnapshot
}

struct ThisWeekProvider: TimelineProvider {
    func placeholder(in context: Context) -> ThisWeekEntry { ThisWeekEntry(date: .now, snapshot: .empty) }

    func getSnapshot(in context: Context, completion: @escaping (ThisWeekEntry) -> Void) {
        completion(ThisWeekEntry(date: .now, snapshot: DashboardSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ThisWeekEntry>) -> Void) {
        let entry = ThisWeekEntry(date: .now, snapshot: DashboardSnapshot.load())
        // The app reloads timelines whenever data changes; this fallback rolls the week over at midnight.
        let calendar = Calendar.current
        let fourHours = calendar.date(byAdding: .hour, value: 4, to: .now) ?? .now
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? fourHours
        completion(Timeline(entries: [entry], policy: .after(min(fourHours, midnight))))
    }
}

/// Tasks due in the next seven days, with a flag on high-priority ones. Tap to open the Tasks page.
struct ThisWeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ThisWeekWidget", provider: ThisWeekProvider()) { entry in
            ThisWeekWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "cpamanager://tasks"))
        }
        .configurationDisplayName("This Week")
        .description("Tasks due in the next seven days. Tap to open your Tasks page.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

struct ThisWeekWidgetView: View {
    var entry: ThisWeekEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: DashboardSnapshot { entry.snapshot }
    private var items: [DashboardSnapshot.Item] { snapshot.weekItems ?? [] }
    private var count: Int { snapshot.weekCount ?? items.count }
    private var high: Int { snapshot.weekHighCount ?? 0 }

    var body: some View {
        switch family {
        case .systemSmall:          smallView
        case .systemMedium:         listView(limit: 4)
        case .systemLarge:          listView(limit: 9)
        case .accessoryRectangular: rectangularView
        case .accessoryInline:      Text(count == 0 ? "Nothing due this week" : "\(count) due this week")
        default:                    listView(limit: 4)
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "calendar")
                Text("This week").font(.caption.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(Theme.brand)
            Text("\(count)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
            Text("tasks due").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if high > 0 {
                Label("\(high) high priority", systemImage: "flag.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.bad)
            } else if snapshot.overdueCount > 0 {
                Label("\(snapshot.overdueCount) overdue", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.bad)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func listView(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "calendar").foregroundStyle(Theme.brand)
                Text("This week").font(.subheadline.weight(.semibold))
                Spacer()
                if high > 0 {
                    Text("\(high) high").font(.caption2.weight(.semibold)).foregroundStyle(Theme.bad)
                }
                Text("\(count) due").font(.caption2.weight(.semibold)).foregroundStyle(Theme.alert)
            }
            if items.isEmpty {
                Spacer()
                Text("Nothing due this week")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ForEach(items.prefix(limit)) { item in row(item) }
                if count > min(limit, items.count) {
                    Text("+ \(count - min(limit, items.count)) more").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ item: DashboardSnapshot.Item) -> some View {
        HStack(spacing: 8) {
            Button(intent: CompleteTaskIntent(taskID: item.id.uuidString)) {
                Image(systemName: "circle").font(.body).foregroundStyle(Theme.brand)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(item.title)")
            Text(item.title).font(.caption).lineLimit(1)
            if item.isHigh == true {
                Image(systemName: "flag.fill").font(.caption2).foregroundStyle(Theme.bad).accessibilityLabel("High priority")
            }
            Spacer(minLength: 4)
            if let due = item.dueDate {
                Text(Format.relativeDay(due)).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(count) due this week" + (high > 0 ? " • \(high) high" : "")).font(.caption.weight(.semibold))
            if items.isEmpty {
                Text("All clear").font(.caption2)
            } else {
                ForEach(items.prefix(2)) { item in Text("• \(item.title)").font(.caption2).lineLimit(1) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
