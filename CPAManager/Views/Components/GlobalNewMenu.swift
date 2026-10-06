import SwiftUI

/// The big "New" button. On iPad and Mac it sits at the top of the sidebar; on iPhone it floats
/// above the tab bar. New Tax Return is first because it is what the owner starts most.
struct GlobalNewMenu: View {
    enum Style { case sidebar, floating }

    var style: Style

    @Environment(AppRouter.self) private var router

    var body: some View {
        Menu {
            Button { router.creating = .taxReturn } label: {
                Label("New Tax Return", systemImage: "doc.text.fill")
            }
            Divider()
            Button { router.creating = .client } label: {
                Label("New Client", systemImage: "person.badge.plus")
            }
            Button { router.creating = .project } label: {
                Label("New Project", systemImage: "folder.badge.plus")
            }
            Button { router.go(to: .today, focus: .newTask) } label: {
                Label("New Task", systemImage: "checkmark.circle")
            }
            Button { router.go(to: .inbox, focus: .inboxCapture) } label: {
                Label("Capture to Inbox", systemImage: "tray.and.arrow.down")
            }
        } label: {
            switch style {
            case .sidebar:
                Label("New", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.brand, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            case .floating:
                Label("New", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    .background(Theme.brand, in: Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            }
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: style == .floating, vertical: false)
        .accessibilityLabel("New")
        .accessibilityHint("Start a tax return, client, project or task")
    }
}
