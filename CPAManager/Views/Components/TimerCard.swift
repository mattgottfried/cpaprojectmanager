import SwiftUI
import SwiftData

/// The running-timer banner shown on the dashboard.
struct TimerCard: View {
    @Environment(TimerController.self) private var timer
    @Environment(\.modelContext) private var context

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TIMING")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.8))
                Text(timer.label)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let start = timer.startedAt {
                    Text(timerInterval: start...Date.distantFuture, countsDown: false)
                        .font(.title2.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            Spacer()
            Button {
                timer.stop(context: context)
            } label: {
                Image(systemName: "stop.fill")
                    .accessibilityLabel("Stop timer")
                    .font(.title2)
                    .foregroundStyle(Theme.brand)
                    .frame(width: 52, height: 52)
                    .background(.white, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(
            LinearGradient(colors: [Theme.brand, Theme.brandDark], startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }
}
