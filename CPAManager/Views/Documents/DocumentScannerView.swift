import SwiftUI
import VisionKit
import PDFKit

// VNDocumentCameraViewController has no Mac Catalyst equivalent — guard the whole
// file so a Catalyst build doesn't even try to compile against it. The one caller
// (DocumentsSectionView) already hides the entry point on Catalyst to match.
#if !targetEnvironment(macCatalyst)

/// Wraps `VNDocumentCameraViewController` to scan one or more pages with the
/// camera and combine them into a single PDF, handed back via `onComplete`.
struct DocumentScannerView: UIViewControllerRepresentable {
    var onComplete: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete, dismiss: dismiss)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onComplete: (Data) -> Void
        let dismiss: DismissAction

        init(onComplete: @escaping (Data) -> Void, dismiss: DismissAction) {
            self.onComplete = onComplete
            self.dismiss = dismiss
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let pdf = PDFDocument()
            for pageIndex in 0..<scan.pageCount {
                let image = scan.imageOfPage(at: pageIndex)
                if let page = PDFPage(image: image) {
                    pdf.insert(page, at: pdf.pageCount)
                }
            }
            if let data = pdf.dataRepresentation() {
                onComplete(data)
            }
            dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            dismiss()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            dismiss()
        }
    }
}

#endif
