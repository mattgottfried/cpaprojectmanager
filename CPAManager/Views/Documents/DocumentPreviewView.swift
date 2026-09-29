import SwiftUI
#if os(iOS)
import QuickLook
#else
import AppKit
#endif

/// Previews a `Document` using QuickLook. Document bytes live in SwiftData
/// external storage, but QuickLook needs a real file URL, so this writes a
/// temporary copy each time it's shown.
struct DocumentPreviewView: View {
    let document: Document
    @Environment(\.dismiss) private var dismiss
    @State private var fileURL: URL?

    var body: some View {
        Group {
            #if os(iOS)
            if let fileURL {
                QuickLookPreview(url: fileURL)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            #else
            // Mac: hand the file to Preview / the default app instead of embedding QuickLook.
            ProgressView("Opening \(document.displayName)…")
                .padding(30)
            #endif
        }
        .task {
            writeTempFile()
            #if os(macOS)
            if let fileURL { NSWorkspace.shared.open(fileURL) }
            dismiss()
            #endif
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white, .black.opacity(0.5))
                    .padding()
            }
        }
    }

    private func writeTempFile() {
        let name = document.filename.isEmpty ? "Document" : document.filename
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("\(name).\(document.fileExtension)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try document.data.write(to: url)
            fileURL = url
        } catch {
            fileURL = nil
        }
    }
}

#if os(iOS)
/// UIKit QuickLook bridge.
private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
#endif
