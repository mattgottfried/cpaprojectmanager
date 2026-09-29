import SwiftUI

/// A transient "did it — undo?" message. Optimistic actions show one of these
/// instead of a confirmation dialog.
struct UndoToastState: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var systemImage: String = "checkmark.circle.fill"
    /// Nil for a plain notice with nothing to undo.
    var undo: (() -> Void)? = nil

    static func == (lhs: UndoToastState, rhs: UndoToastState) -> Bool { lhs.id == rhs.id }
}

private struct UndoToastView: View {
    let toast: UndoToastState
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.systemImage).foregroundStyle(.secondary)
            Text(toast.message).font(.subheadline).lineLimit(1)
            Spacer(minLength: 8)
            if let undo = toast.undo {
                Button("Undo") {
                    undo()
                    dismiss()
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Shows `toast` at the bottom for ~4 seconds, then clears the binding.
    func undoToast(_ toast: Binding<UndoToastState?>) -> some View {
        overlay(alignment: .bottom) {
            if let current = toast.wrappedValue {
                UndoToastView(toast: current) { toast.wrappedValue = nil }
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: current.id) {
                        try? await Task.sleep(for: .seconds(4))
                        if toast.wrappedValue?.id == current.id {
                            toast.wrappedValue = nil
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: toast.wrappedValue?.id)
        .sensoryFeedback(.impact(weight: .light), trigger: toast.wrappedValue?.id)
    }
}
