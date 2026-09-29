import WidgetKit
import SwiftUI
import AppIntents

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
        // The app reloads timelines whenever data changes; this is just a fallback,
        // capped at midnight so "today" rolls over on time.
        let calendar = Calendar.current
        let fourHours = calendar.date(byAdding: .hour, value: 4, to: .now) ?? .now
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? fourHours
        completion(Timeline(entries: [entry], policy: .after(min(fourHours, midnight))))
    }
}

struct DueTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DueTodayWidget", provider: DueTodayProvider()) { entry in
            DueTodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "cpamanager://today"))
        }
        .configurationDisplayName("Today")
        .description("Overdue, due today, and next-up work. Tap a circle to check it off; tap + to add a task.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

struct DueTodayWidgetView: View {
    var entry: DueTodayEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: DashboardSnapshot { entry.snapshot }
    /// Today-screen order; falls back to the older "upcoming" list for snapshots
    /// written by a previous build.
    private var items: [DashboardSnapshot.Item] { snapshot.todayItems ?? snapshot.upcoming }
    private var needsAttention: Int { snapshot.overdueCount + snapshot.dueTodayCount }

    var body: some View {
        switch family {
        case .systemSmall:           smallView
        case .systemMedium:          listView(limit: 4)
        case .systemLarge:           listView(limit: 9)
        case .accessoryCircular:     circularView
        case .accessoryRectangular:  rectangularView
        case .accessoryInline:       inlineView
        default:                     listView(limit: 4)
        }
    }

    // MARK: Home screen

    private var addLink: some View {
        Link(destination: URL(string: "cpamanager://capture")!) {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.brand)
        }
        .accessibilityLabel("Add a task")
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "sun.max.fill")
                Text("Today").font(.caption.weight(.semibold))
                Spacer()
                addLink
            }
            .foregroundStyle(Theme.brand)

            Text("\(snapshot.dueTodayCount)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
            Text("due today")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if snapshot.overdueCount > 0 {
                Label("\(snapshot.overdueCount) overdue", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.bad)
            } else if let inbox = snapshot.inboxCount, inbox > 0 {
                Label("\(inbox) in inbox", systemImage: "tray.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.info)
            } else {
                Label("\(snapshot.openProjectCount) open", systemImage: "tray.full")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func listView(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sun.max.fill").foregroundStyle(Theme.brand)
                Text("Today").font(.subheadline.weight(.semibold))
                Spacer()
                if snapshot.overdueCount > 0 {
                    Text("\(snapshot.overdueCount) overdue")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.bad)
                }
                Text("\(snapshot.dueTodayCount) today")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.alert)
                addLink
            }

            if items.isEmpty {
                Spacer()
                Text("All clear")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ForEach(items.prefix(limit)) { item in
                    row(item)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ item: DashboardSnapshot.Item) -> some View {
        HStack(spacing: 8) {
            if item.isTask == true {
                Button(intent: CompleteTaskIntent(taskID: item.id.uuidString)) {
                    Image(systemName: "circle")
                        .font(.body)
                        .foregroundStyle(item.isOverdue ? Theme.bad : Theme.brand)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Complete \(item.title)")
            } else {
                Image(systemName: "folder.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 17)
                    .accessibilityHidden(true)
            }
            Text(item.title)
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let due = item.dueDate {
                Label(Format.relativeDay(due), systemImage: item.isOverdue ? "exclamationmark.triangle.fill" : "calendar")
                    .labelStyle(.titleOnly)
                    .font(.caption2)
                    .foregroundStyle(item.isOverdue ? Theme.bad : .secondary)
            }
        }
    }

    // MARK: Lock screen

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: snapshot.overdueCount > 0 ? "exclamationmark.triangle.fill" : "sun.max.fill")
                    .font(.caption2)
                Text("\(needsAttention)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
            }
        }
        .accessibilityLabel("\(snapshot.overdueCount) overdue, \(snapshot.dueTodayCount) due today")
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(snapshot.dueTodayCount) today • \(snapshot.overdueCount) overdue")
                .font(.caption.weight(.semibold))
            if items.isEmpty {
                Text("All clear").font(.caption2)
            } else {
                ForEach(items.prefix(2)) { item in
                    Text("• \(item.title)").font(.caption2).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inlineView: some View {
        Text(needsAttention == 0
             ? "Nothing due today"
             : "\(snapshot.dueTodayCount) due • \(snapshot.overdueCount) overdue")
    }
}
