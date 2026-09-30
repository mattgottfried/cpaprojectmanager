import SwiftUI

// Mac-only polish, as no-ops on iOS/iPadOS so shared screens can call them freely.

extension View {
    /// Card-style grouped forms on the Mac (iOS already draws forms that way). Applied once
    /// at each window root; the environment carries it into sheets and pushed screens.
    @ViewBuilder
    func appChrome() -> some View {
        #if os(macOS)
        self.formStyle(.grouped)
        #else
        self
        #endif
    }

    /// Mac sheets don't size themselves to a form — give them a comfortable, resizable size.
    @ViewBuilder
    func macSheetFrame(minWidth: CGFloat = 480, idealWidth: CGFloat = 540,
                       minHeight: CGFloat = 440, idealHeight: CGFloat = 600) -> some View {
        #if os(macOS)
        self.frame(minWidth: minWidth, idealWidth: idealWidth, minHeight: minHeight, idealHeight: idealHeight)
        #else
        self
        #endif
    }

    /// Keeps card lists and forms at a readable width in a big Mac window, centered on the
    /// window background instead of stretching edge to edge.
    @ViewBuilder
    func macReadableWidth(_ maxWidth: CGFloat = 860) -> some View {
        #if os(macOS)
        self.frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
            .background(Color.appGroupedBackground)
        #else
        self
        #endif
    }

    /// Smallest size the main window can shrink to on the Mac.
    @ViewBuilder
    func macWindowMinSize(width: CGFloat = 900, height: CGFloat = 600) -> some View {
        #if os(macOS)
        self.frame(minWidth: width, minHeight: height)
        #else
        self
        #endif
    }

    /// A right-click / long-press Delete for rows — the Mac has no swipe-to-delete.
    func deleteMenu(_ title: String = "Delete", action: @escaping () -> Void) -> some View {
        contextMenu {
            Button(role: .destructive, action: action) {
                Label(title, systemImage: "trash")
            }
        }
    }
}

/// A `List` on iOS; a grouped, card-style `Form` on the Mac, where plain lists of sections
/// look like an unstyled table. Use for detail screens made of sections (not card lists).
struct GroupedList<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if os(macOS)
        Form { content() }
            .formStyle(.grouped)
        #else
        List { content() }
        #endif
    }
}

extension View {
    /// Right-click / long-press Delete for a row of a list that already deletes by swipe
    /// (`.onDelete`), reusing its IndexSet handler — the Mac has no swipe.
    func deleteMenu<Item: Identifiable>(
        of item: Item, in items: [Item], title: String = "Delete", perform delete: @escaping (IndexSet) -> Void
    ) -> some View {
        deleteMenu(title) {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                delete(IndexSet(integer: index))
            }
        }
    }
}
