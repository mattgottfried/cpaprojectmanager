import SwiftUI

/// Today is three screens behind one switcher: Focus (the daily plan), Tasks (every task in
/// a table, board or calendar) and Insights (the dashboard).
enum TodayMode: String, CaseIterable, Identifiable {
    case focus = "Focus"
    case tasks = "Tasks"
    case insights = "Insights"

    var id: String { rawValue }
    static let storageKey = "todayMode"
}

/// The segmented switcher each of the three screens puts in its toolbar.
struct TodayModePicker: View {
    @AppStorage(TodayMode.storageKey) private var raw = TodayMode.focus.rawValue

    var body: some View {
        Picker("View", selection: $raw) {
            ForEach(TodayMode.allCases) { Text($0.rawValue).tag($0.rawValue) }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 300)
        .accessibilityLabel("Today view")
    }
}

struct TodayHubView: View {
    @AppStorage(TodayMode.storageKey) private var raw = TodayMode.focus.rawValue
    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            switch TodayMode(rawValue: raw) ?? .focus {
            case .focus:    TodayView()
            case .tasks:    TasksPageView()
            case .insights: InsightsView()
            }
        }
        // "New task" (⌘N, widgets) lands on the Focus screen, where the capture bar is.
        .onChange(of: router.pendingFocus) { _, new in
            if new != nil { raw = TodayMode.focus.rawValue }
        }
    }
}
