import UIKit

/// AirPrint via `UIPrintInteractionController` directly, rather than relying on
/// "Print" showing up inside the system share sheet — it doesn't reliably appear
/// there on Mac (Catalyst's share picker doesn't always surface a print service).
enum PrintHelper {
    static func printPDF(at url: URL, jobName: String) {
        guard let data = try? Data(contentsOf: url) else { return }

        let printInfo = UIPrintInfo(dutyCycle: .low)
        printInfo.outputType = .general
        printInfo.jobName = jobName

        let controller = UIPrintInteractionController.shared
        controller.printInfo = printInfo
        controller.printingItem = data

        // presentFromRect (rather than the plain `present`) is the one variant that
        // behaves correctly across iPhone, iPad (where it anchors a popover), and
        // Mac Catalyst (which just shows the print panel) without branching per idiom.
        if let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
           let rootView = scene.keyWindow?.rootViewController?.view {
            controller.present(from: rootView.bounds, in: rootView, animated: true, completionHandler: nil)
        } else {
            controller.present(animated: true, completionHandler: nil)
        }
    }
}
