import SwiftUI

// Reusable pieces of the visual language in docs/DESIGN.md. Use these instead of
// re-deriving radii, paddings, or tints per screen.

/// The everyday repeating card: 14pt continuous corners, dense padding, optional
/// colored outline for a featured state, dimmed when inactive.
struct RowCardModifier: ViewModifier {
    var dimmed = false
    var outline: Color? = nil
    /// Mac pointer hover: a faint brand tint so rows feel clickable.
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color.appCardBackground)
            .overlay {
                #if os(macOS)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.brand.opacity(hovering ? 0.07 : 0))
                    .allowsHitTesting(false)
                #endif
            }
            #if os(macOS)
            .onHover { hovering = $0 }
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                if let outline {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(outline.opacity(0.6), lineWidth: 1.5)
                }
            }
            .opacity(dimmed ? 0.6 : 1)
    }
}

extension View {
    func rowCard(dimmed: Bool = false, outline: Color? = nil) -> some View {
        modifier(RowCardModifier(dimmed: dimmed, outline: outline))
    }

    /// Makes a `List` row render as a free-standing card on the grouped background.
    func cardListRow() -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

/// Small rounded-square tile that is the first thing the eye hits in a row: an icon
/// tinted by a semantic state.
struct StatusTile: View {
    let systemImage: String
    var state: SemanticState = .neutral
    var size: CGFloat = 44

    var body: some View {
        let color = Theme.color(state)
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .bold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.21, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Titled dashboard/section card (16pt radius) — icon + title header, then content.
struct SectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    var state: SemanticState = .info
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Theme.color(state))
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Number + label pair, used in rows of 2–4 across the top of a summary screen.
struct StatChip: View {
    let value: String
    let label: String
    var state: SemanticState = .info

    var body: some View {
        let color = Theme.color(state)
        VStack(spacing: 3) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Small status pill. Always icon + word, never color alone. `solid` is for urgent
/// or rare states; the tinted style is for normal, frequent ones.
struct CapsuleBadge: View {
    let text: String
    var systemImage: String? = nil
    var state: SemanticState = .neutral
    var solid = false

    var body: some View {
        let color = Theme.color(state)
        Group {
            if let systemImage {
                Label(text, systemImage: systemImage)
            } else {
                Text(text)
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(solid ? Color.white : color)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(solid ? color : color.opacity(0.12), in: Capsule())
    }
}
