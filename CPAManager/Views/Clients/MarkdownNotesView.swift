import SwiftUI

/// Renders client notes (a small Markdown subset: headings, bullets, checkboxes) and lets
/// checkboxes be ticked in place. Plain-text notes render as-is.
struct MarkdownNotesView: View {
    @Binding var text: String

    var body: some View {
        let blocks = MarkdownBlocks.parse(text)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                row(block, lineIndex: index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func row(_ block: MarkdownBlock, lineIndex: Int) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(level == 1 ? .title3.bold() : level == 2 ? .headline : .subheadline.weight(.semibold))
                .padding(.top, 4)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                Text(inline(text))
            }
        case .checkbox(let checked, let text):
            Button {
                self.text = MarkdownBlocks.toggleCheckbox(in: self.text, lineIndex: lineIndex)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(checked ? Theme.brand : .secondary)
                    Text(inline(text))
                        .strikethrough(checked)
                        .foregroundStyle(checked ? .secondary : .primary)
                        .multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(text)
            .accessibilityValue(checked ? "Done" : "Not done")
            .accessibilityAddTraits(.isButton)
        case .paragraph(let text):
            Text(inline(text))
        case .blank:
            Color.clear.frame(height: 4)
        }
    }

    /// Bold, italic, code and links inside a line.
    private func inline(_ string: String) -> AttributedString {
        (try? AttributedString(markdown: string, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(string)
    }
}
