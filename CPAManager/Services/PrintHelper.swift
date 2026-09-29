import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
import PDFKit
#endif

#if canImport(UIKit)
/// AirPrint via `UIPrintInteractionController` directly, rather than relying on
/// "Print" showing up inside the system share sheet — it doesn't reliably appear
/// there on Mac (Catalyst's share picker doesn't always surface a print service).
enum PrintHelper {
    static func printPDF(at url: URL, jobName: String) {
        guard let data = try? Data(contentsOf: url) else {
            print("PrintHelper: couldn't read PDF data at \(url)")
            return
        }

        let printInfo = UIPrintInfo.printInfo()
        printInfo.outputType = .general
        printInfo.jobName = jobName

        let controller = UIPrintInteractionController.shared
        controller.printInfo = printInfo
        controller.printingItem = data

        let completion: UIPrintInteractionController.CompletionHandler = { _, completed, error in
            if let error {
                print("PrintHelper: print failed — \(error)")
            } else if !completed {
                print("PrintHelper: print panel closed without completing (cancelled, or no printer selected)")
            } else {
                print("PrintHelper: print completed")
            }
        }

        // presentFromRect (rather than the plain `present`) is the one variant that
        // behaves correctly across iPhone, iPad (where it anchors a popover), and
        // Mac Catalyst (which just shows the print panel) without branching per idiom.
        if let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
           let rootView = scene.keyWindow?.rootViewController?.view {
            let didPresent = controller.present(from: rootView.bounds, in: rootView, animated: true, completionHandler: completion)
            print("PrintHelper: presentFromRect returned \(didPresent)")
        } else {
            print("PrintHelper: no foreground-active window scene found — falling back to present(animated:)")
            let didPresent = controller.present(animated: true, completionHandler: completion)
            print("PrintHelper: present(animated:) returned \(didPresent)")
        }
    }
}
#else
/// macOS: the standard print panel for a PDF, via PDFKit.
enum PrintHelper {
    @MainActor
    static func printPDF(at url: URL, jobName: String) {
        guard let document = PDFDocument(url: url) else { return }
        let info = NSPrintInfo.shared
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        guard let operation = document.printOperation(for: info, scalingMode: .pageScaleDownToFit, autoRotate: true) else { return }
        operation.jobTitle = jobName
        operation.showsPrintPanel = true
        operation.run()
    }
}
#endif
