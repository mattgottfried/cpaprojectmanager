import Foundation
import UIKit

/// Renders a printable routing sheet PDF (US Letter) for a project's task
/// checklist, in the same spirit as the firm's paper routing sheets — client
/// info up top, then a numbered checklist with a Done column and a Date/Notes
/// column. Works for any project with tasks, not just ones created from the
/// "Tax Return Routing Sheet" / "IRS Notice Routing Sheet" templates.
enum RoutingSheetPDF {
    static func generate(project: Project, firmName: String) -> URL? {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 48
        let contentWidth = pageWidth - margin * 2

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let data = renderer.pdfData { rendererContext in
            rendererContext.beginPage()
            var y: CGFloat = margin

            func draw(_ text: String, font: UIFont, color: UIColor = .black) {
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let bounding = (text as NSString).boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: .usesLineFragmentOrigin,
                    attributes: attrs,
                    context: nil
                )
                (text as NSString).draw(
                    in: CGRect(x: margin, y: y, width: contentWidth, height: bounding.height),
                    withAttributes: attrs
                )
                y += ceil(bounding.height) + 4
            }

            func field(_ label: String, _ value: String) {
                draw(label.uppercased(), font: .boldSystemFont(ofSize: 9), color: .darkGray)
                draw(value.isEmpty ? "—" : value, font: .systemFont(ofSize: 12))
                y += 6
            }

            draw(firmName.isEmpty ? "Routing Sheet" : firmName, font: .boldSystemFont(ofSize: 18))
            draw("\(project.templateName ?? project.serviceType.label) — Routing Sheet".uppercased(),
                 font: .boldSystemFont(ofSize: 12), color: .darkGray)
            y += 8

            field("Client", project.clientName)
            if project.serviceType == .taxReturn, project.taxYear > 0 {
                field("Tax Year", String(project.taxYear))
            }
            if let received = project.receivedDate {
                field("Date Received", Format.mediumDate.string(from: received))
            }
            if let due = project.dueDate {
                field("Due Date", Format.mediumDate.string(from: due))
            }
            field("Priority", project.priority.label)
            y += 8

            UIColor.lightGray.setFill()
            UIRectFill(CGRect(x: margin, y: y, width: contentWidth, height: 0.75))
            y += 12

            let numX = margin
            let taskX = margin + 26
            let doneX = pageWidth - margin - 150
            let noteX = pageWidth - margin - 110
            let taskWidth = doneX - taskX - 8
            let noteWidth = pageWidth - margin - noteX

            func drawTableHeader() {
                let headerAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 10)]
                ("#" as NSString).draw(at: CGPoint(x: numX, y: y), withAttributes: headerAttrs)
                ("Workflow Stage" as NSString).draw(at: CGPoint(x: taskX, y: y), withAttributes: headerAttrs)
                ("Done" as NSString).draw(at: CGPoint(x: doneX, y: y), withAttributes: headerAttrs)
                ("Date / Notes" as NSString).draw(at: CGPoint(x: noteX, y: y), withAttributes: headerAttrs)
                y += 16
                UIColor.lightGray.setFill()
                UIRectFill(CGRect(x: margin, y: y, width: contentWidth, height: 0.75))
                y += 8
            }

            drawTableHeader()

            let rowFont = UIFont.systemFont(ofSize: 10)
            let rowAttrs: [NSAttributedString.Key: Any] = [.font: rowFont]

            if project.taskList.isEmpty {
                draw("No checklist items on this project.", font: .italicSystemFont(ofSize: 10), color: .darkGray)
            }

            for (index, task) in project.taskList.enumerated() {
                let bounding = (task.title as NSString).boundingRect(
                    with: CGSize(width: taskWidth, height: .greatestFiniteMagnitude),
                    options: .usesLineFragmentOrigin,
                    attributes: rowAttrs,
                    context: nil
                )
                let rowHeight = max(18, ceil(bounding.height) + 6)

                if y + rowHeight > pageHeight - margin {
                    rendererContext.beginPage()
                    y = margin
                    drawTableHeader()
                }

                ("\(index + 1)" as NSString).draw(at: CGPoint(x: numX, y: y), withAttributes: rowAttrs)
                (task.title as NSString).draw(
                    in: CGRect(x: taskX, y: y, width: taskWidth, height: bounding.height),
                    withAttributes: rowAttrs
                )
                ((task.isDone ? "X" : "") as NSString).draw(at: CGPoint(x: doneX, y: y), withAttributes: rowAttrs)

                let noteText = task.completedAt.map { Format.shortDate.string(from: $0) } ?? task.notes
                (noteText as NSString).draw(
                    in: CGRect(x: noteX, y: y, width: noteWidth, height: bounding.height),
                    withAttributes: rowAttrs
                )

                y += rowHeight
            }
        }

        let safeTitle = project.title
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespaces)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Routing Sheet - \(safeTitle)-\(UUID().uuidString.prefix(6)).pdf")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
