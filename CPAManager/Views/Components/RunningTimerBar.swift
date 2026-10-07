import SwiftUI

/// The running timer, on every screen: what it's timing, a live clock, and a Stop button. At the
/// bottom of the sidebar on iPad and Mac; floating above the tab bar on iPhone. Shows nothing
/// when no timer is running.
struct RunningTimerBar: View {
    enum Style { case sidebar, floating }

    var style: Style

    @Environment(TimerController.self) private var timer
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context

    var body: some View {
        if timer.isRunning {
            bar
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var bar: some View {
        HStack(spacing: 10) {
            Button {
                if style == .sidebar { router.go(to: .time) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "timer")
                        .font(.title3)
                        .foregroundStyle(Theme.brand)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(timer.label.isEmpty ? "Timer running" : timer.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text(Format.clock(timer.elapsedSeconds))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                timer.stop(context: context)
            } label: {
                Image(systemName: "stop.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Theme.bad, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop timer")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(background)
        .frame(maxWidth: style == .floating ? 240 : .infinity)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .sidebar:
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.appCardBackground)
        case .floating:
            Capsule().fill(Color.appCardBackground).shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        }
    }
}
