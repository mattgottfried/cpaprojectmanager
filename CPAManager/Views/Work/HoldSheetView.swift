import SwiftUI
import SwiftData

/// Puts a project on hold with a reason, mirroring the firm's "Put On Hold"
/// Shortcut (a reason category paired with a free-text detail).
struct HoldSheetView: View {
    @Bindable var project: Project
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var reason: HoldReason = .waitingOnClient
    @State private var detail = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Reason", selection: $reason) {
                    ForEach(HoldReason.allCases) { Text($0.label).tag($0) }
                }
                TextField("What are we waiting on?", text: $detail, axis: .vertical)
                    .lineLimit(2...5)
            }
            .navigationTitle(project.statusFlow == .taxReturn ? "Put on Hold" : "Waiting on Client")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(project.statusFlow == .taxReturn ? "Hold" : "Save") {
                        project.putOnHold(reason: reason, detail: detail.trimmingCharacters(in: .whitespaces))
                        PipelineEngine.runBuiltInAutomation(project, context: context)
                        try? context.save()
                        SnapshotBuilder.rebuild(context: context)
                        NotificationScheduler.rescheduleAll(context: context)
                        dismiss()
                    }
                }
            }
        }
        .macSheetFrame()
    }
}
