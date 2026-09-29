import SwiftUI

#if os(iOS)
/// UIActivityViewController bridge for sharing files (PDFs, etc.) via
/// email, Messages, AirDrop, and so on.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
import AppKit

/// macOS counterpart: a small sheet with the system share menu, "Show in Finder",
/// and "Open" for each file, since Mac has no share-sheet controller to embed.
struct ShareSheet: View {
    let items: [Any]
    @Environment(\.dismiss) private var dismiss

    private var urls: [URL] { items.compactMap { $0 as? URL } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Share").font(.headline)
            ForEach(urls, id: \.self) { url in
                HStack(spacing: 10) {
                    Image(systemName: "doc.fill").foregroundStyle(Theme.brand)
                    Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                    Button { NSWorkspace.shared.open(url) } label: { Label("Open", systemImage: "arrow.up.forward.app") }
                    Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Label("Show in Finder", systemImage: "folder") }
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
    }
}
#endif
