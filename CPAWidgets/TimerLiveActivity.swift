import WidgetKit
import SwiftUI
import ActivityKit

/// Lock-screen and Dynamic Island presentation of the billable-hours timer.
struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(Theme.brand.opacity(0.18))
                .activitySystemActionForegroundColor(Theme.brand)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Timing", systemImage: "timer")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(context.attributes.projectTitle)
                            .font(.headline)
                            .lineLimit(1)
                        if !context.attributes.clientName.isEmpty {
                            Text(context.attributes.clientName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                        .font(.title2.monospacedDigit().bold())
                        .foregroundStyle(Theme.brand)
                        .frame(maxWidth: 90)
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isBillable {
                        Label("Billable", systemImage: "dollarsign.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(Theme.brand)
            } compactTrailing: {
                Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                    .monospacedDigit()
                    .frame(maxWidth: 44)
                    .foregroundStyle(Theme.brand)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(Theme.brand)
            }
            .keylineTint(Theme.brand)
        }
    }

    private func lockScreen(_ context: ActivityViewContext<TimerActivityAttributes>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "timer")
                .font(.title2)
                .foregroundStyle(Theme.brand)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.projectTitle)
                    .font(.headline)
                    .lineLimit(1)
                if !context.attributes.clientName.isEmpty {
                    Text(context.attributes.clientName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                .font(.title.monospacedDigit().bold())
                .foregroundStyle(Theme.brand)
                .frame(maxWidth: 110)
        }
        .padding()
    }
}
