import SwiftUI

// Shared pieces of the select-several / keyboard-cursor behavior on the Work and Clients
// lists (logic in `ListSelection`, Services/ListInteractionLogic.swift).

/// The bar shown at the bottom of a list while rows are being selected.
struct BulkBar<Actions: View>: View {
    let count: Int
    let done: () -> Void
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(spacing: 14) {
            Button("Done", action: done)
                .font(.subheadline.weight(.semibold))
            Text(count == 0 ? "Select items" : "\(count) selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            actions()
                .disabled(count == 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial)
    }
}

/// Picks one date for a bulk "set due date".
struct BulkDateSheet: View {
    let title: String
    let onApply: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Due date", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
            }
            .navigationTitle(title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { onApply(date); dismiss() }
                }
            }
        }
        .macSheetFrame(minWidth: 360, idealWidth: 400, minHeight: 420, idealHeight: 460)
        .presentationDetents([.medium, .large])
    }
}

/// One selectable row: a check circle while selecting, the plain row otherwise. Draws an
/// outline on the row the Mac keyboard cursor is on.
struct SelectableRow<Row: View, Link: View>: View {
    let isSelecting: Bool
    let isSelected: Bool
    let isCursor: Bool
    let toggle: () -> Void
    @ViewBuilder var row: () -> Row
    @ViewBuilder var link: () -> Link

    var body: some View {
        Group {
            if isSelecting {
                Button(action: toggle) {
                    HStack(spacing: 10) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? Theme.brand : Color.secondary)
                            .accessibilityHidden(true)
                        row()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            } else {
                link()
            }
        }
        .overlay {
            if isCursor {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.brand.opacity(0.7), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    /// Mac keyboard control for a list: ↑/↓ move a cursor, Return opens, Space selects,
    /// Delete removes. No-op elsewhere.
    @ViewBuilder
    func listKeyboard(
        move: @escaping (Int) -> Void,
        open: @escaping () -> Void,
        toggle: @escaping () -> Void,
        delete: @escaping () -> Void
    ) -> some View {
        #if os(macOS)
        self
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.downArrow) { move(1); return .handled }
            .onKeyPress(.upArrow) { move(-1); return .handled }
            .onKeyPress(.return) { open(); return .handled }
            .onKeyPress(.space) { toggle(); return .handled }
            .onKeyPress(.delete) { delete(); return .handled }
        #else
        self
        #endif
    }
}
