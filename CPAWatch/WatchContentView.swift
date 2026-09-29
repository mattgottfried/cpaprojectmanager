import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        NavigationStack {
            List {
                timerSection
                summarySection
                tasksSection
            }
            .navigationTitle("Today")
        }
    }

    private var timerSection: some View {
        Section {
            Button {
                store.toggleTimer()
            } label: {
                if let start = store.payload.timerStartedAt {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Stop timer", systemImage: "stop.circle.fill")
                            .foregroundStyle(.red)
                        Text(timerInterval: start...Date.distantFuture, countsDown: false)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label("Start timer", systemImage: "play.circle.fill")
                }
            }
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        if store.hasData {
            Section {
                HStack {
                    stat("\(store.payload.overdueCount)", "Overdue", store.payload.overdueCount > 0 ? .red : .secondary)
                    Spacer()
                    stat("\(store.payload.dueTodayCount)", "Due today", .blue)
                }
            }
        } else {
            Section {
                Text("Open CPA Manager on your iPhone to sync.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.title3.bold()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var tasksSection: some View {
        if store.hasData && store.payload.tasks.isEmpty {
            Section {
                Label("All clear", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            }
        }
        ForEach(store.payload.tasks) { task in
            HStack(spacing: 8) {
                if task.isTask {
                    Button {
                        store.complete(task)
                    } label: {
                        Image(systemName: "circle")
                            .foregroundStyle(task.isOverdue ? .red : .blue)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Complete \(task.title)")
                } else {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title).lineLimit(2)
                    if !task.subtitle.isEmpty {
                        Text(task.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }
}
