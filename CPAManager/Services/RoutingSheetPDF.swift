import Foundation
import UIKit

/// Renders a printable routing sheet PDF (US Letter), matching the firm's actual
/// paper routing sheet layout: a letterhead-style header, a bordered client-info
/// grid (Tax Return vs IRS Notice have different fields), a bordered checklist
/// table built from the project's tasks, and a notes box at the bottom. Known
/// data fills in what we have; anything the app doesn't model (e.g. IRS notice
/// number, Form 2848 status) prints as a blank line/checkbox to fill in by hand,
/// same as the paper version.
enum RoutingSheetPDF {
    private static let pageWidth: CGFloat = 612
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 40
    private static var contentWidth: CGFloat { pageWidth - margin * 2 }
    private static var rightEdge: CGFloat { pageWidth - margin }

    static func generate(project: Project, firmName: String, firmTagline: String, firmContact: String) -> URL? {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        let isIRSNotice = project.serviceType == .irsNotice

        let data = renderer.pdfData { rendererContext in
            rendererContext.beginPage()
            var y = drawHeader(project: project, firmName: firmName, firmTagline: firmTagline, firmContact: firmContact)

            y = isIRSNotice ? drawIRSNoticeFields(project: project, y: y) : drawTaxReturnFields(project: project, y: y)
            y += 14

            y = drawChecklist(project: project, y: y, context: rendererContext)
            y += 10
            drawNotesBox(project: project, y: y)
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

    // MARK: Header

    private static func drawHeader(project: Project, firmName: String, firmTagline: String, firmContact: String) -> CGFloat {
        var y = margin
        let title = (project.templateName ?? "\(project.serviceType.label) Routing Sheet").uppercased()

        drawPair(
            left: firmName.isEmpty ? "My Firm" : firmName, leftFont: .boldSystemFont(ofSize: 17),
            right: title, rightFont: .boldSystemFont(ofSize: 12), rightColor: .black,
            y: y
        )
        y += 22

        if !firmTagline.isEmpty || !firmContact.isEmpty {
            drawPair(
                left: firmTagline, leftFont: .systemFont(ofSize: 9), leftColor: .darkGray,
                right: firmContact, rightFont: .systemFont(ofSize: 9), rightColor: .darkGray,
                y: y
            )
            y += 16
        }

        y += 6
        strokeLine(from: CGPoint(x: margin, y: y), to: CGPoint(x: rightEdge, y: y))
        y += 12
        return y
    }

    private static func drawPair(
        left: String, leftFont: UIFont, leftColor: UIColor = .black,
        right: String, rightFont: UIFont, rightColor: UIColor = .black,
        y: CGFloat
    ) {
        (left as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: leftFont, .foregroundColor: leftColor])
        let rightAttrs: [NSAttributedString.Key: Any] = [.font: rightFont, .foregroundColor: rightColor]
        let rightWidth = (right as NSString).size(withAttributes: rightAttrs).width
        (right as NSString).draw(at: CGPoint(x: rightEdge - rightWidth, y: y), withAttributes: rightAttrs)
    }

    // MARK: Client info grid

    private static func drawTaxReturnFields(project: Project, y startY: CGFloat) -> CGFloat {
        var y = startY
        y = drawFullField(label: "Client Name", value: project.clientName, y: y)

        let taxYear = project.taxYear > 0 ? String(project.taxYear) : "—"
        y = drawFieldRow(
            [("Entity / Return Type", project.client?.entityType.label ?? "—"), ("Tax Year", taxYear)],
            y: y
        )
        y = drawFieldRow(
            [
                ("Date Received", project.receivedDate.map(Format.mediumDate.string) ?? "—"),
                ("Actual Due Date", project.dueDate.map(Format.mediumDate.string) ?? "—"),
            ],
            y: y
        )

        let entityType = project.client?.entityType
        let isEarlyGroup = entityType == .partnership1065 || entityType == .sCorp1120S
        let isLateGroup = entityType == .individual1040 || entityType == .cCorp1120
        y = drawFullField(
            label: "Due Date Group",
            value: checkboxLine([
                ("3/15 — Partnership / S-Corporation", isEarlyGroup),
                ("4/15 — Individual / C-Corporation", isLateGroup),
            ]),
            y: y
        )

        let isRush = project.priority == .high
        y = drawFullField(
            label: "Priority",
            value: checkboxLine([
                ("Standard", !isRush),
                ("Rush", isRush),
                ("VIP", false),
                ("On Extension", false),
            ]),
            y: y
        )
        return y
    }

    private static func drawIRSNoticeFields(project: Project, y startY: CGFloat) -> CGFloat {
        var y = startY
        y = drawFullField(label: "Client Name", value: project.clientName, y: y)

        let taxYear = project.taxYear > 0 ? String(project.taxYear) : "—"
        y = drawFieldRow([("Notice Type / CP #", "—"), ("Tax Year", taxYear)], y: y)
        y = drawFieldRow(
            [
                ("Notice Date", project.receivedDate.map(Format.mediumDate.string) ?? "—"),
                ("Response Due", project.dueDate.map(Format.mediumDate.string) ?? "—"),
            ],
            y: y
        )
        y = drawFullField(label: "IRS Office / Address", value: "—", y: y)
        y = drawFieldRow(
            [
                ("Form 2848 on File", checkboxLine([("Yes", false), ("No", false)]) + "   Date signed: \(Format.placeholder)"),
                ("Representation Engaged", checkboxLine([("Yes", false), ("No", false)])),
            ],
            y: y
        )
        return y
    }

    private static func checkboxLine(_ options: [(String, Bool)]) -> String {
        options.map { ($1 ? "☑ " : "☐ ") + $0 }.joined(separator: "     ")
    }

    private static let rowHeight: CGFloat = 30
    private static let fieldLabelFont = UIFont.boldSystemFont(ofSize: 8)
    private static let fieldValueFont = UIFont.systemFont(ofSize: 10.5)

    /// A single full-width bordered cell: label on top, value below.
    private static func drawFullField(label: String, value: String, y: CGFloat) -> CGFloat {
        let rect = CGRect(x: margin, y: y, width: contentWidth, height: rowHeight)
        drawCell(rect, label: label, value: value)
        return y + rowHeight
    }

    /// A row of N equal-width bordered cells, each label-on-top / value-below.
    private static func drawFieldRow(_ fields: [(String, String)], y: CGFloat) -> CGFloat {
        let colWidth = contentWidth / CGFloat(fields.count)
        for (index, field) in fields.enumerated() {
            let rect = CGRect(x: margin + colWidth * CGFloat(index), y: y, width: colWidth, height: rowHeight)
            drawCell(rect, label: field.0, value: field.1)
        }
        return y + rowHeight
    }

    private static func drawCell(_ rect: CGRect, label: String, value: String) {
        strokeRect(rect)
        let inset = rect.insetBy(dx: 6, dy: 4)
        (label.uppercased() as NSString).draw(
            at: CGPoint(x: inset.minX, y: inset.minY),
            withAttributes: [.font: fieldLabelFont, .foregroundColor: UIColor.darkGray]
        )
        (value as NSString).draw(
            at: CGPoint(x: inset.minX, y: inset.minY + 12),
            withAttributes: [.font: fieldValueFont, .foregroundColor: UIColor.black]
        )
    }

    // MARK: Checklist table

    private static var numX: CGFloat { margin }
    private static var stageX: CGFloat { margin + 24 }
    private static var doneX: CGFloat { rightEdge - 196 }
    private static var initialsX: CGFloat { doneX + 36 }
    private static var noteX: CGFloat { initialsX + 50 }
    private static var stageWidth: CGFloat { doneX - stageX - 6 }
    private static var noteWidth: CGFloat { rightEdge - noteX }

    private static func drawChecklist(project: Project, y startY: CGFloat, context: UIGraphicsPDFRendererContext) -> CGFloat {
        var y = startY
        y = drawChecklistHeader(y: y)

        let rowAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9.5)]

        if project.taskList.isEmpty {
            let rect = CGRect(x: margin, y: y, width: contentWidth, height: 20)
            strokeRect(rect)
            ("No checklist items on this project." as NSString).draw(
                at: CGPoint(x: margin + 6, y: y + 5),
                withAttributes: [.font: UIFont.italicSystemFont(ofSize: 9.5), .foregroundColor: UIColor.darkGray]
            )
            return y + 20
        }

        for (index, task) in project.taskList.enumerated() {
            let bounding = (task.title as NSString).boundingRect(
                with: CGSize(width: stageWidth - 8, height: .greatestFiniteMagnitude),
                options: .usesLineFragmentOrigin,
                attributes: rowAttrs,
                context: nil
            )
            let rowH = max(20, ceil(bounding.height) + 8)

            if y + rowH > pageHeight - margin - 90 {
                context.beginPage()
                y = margin
                y = drawChecklistHeader(y: y)
            }

            strokeRect(CGRect(x: numX, y: y, width: stageX - numX, height: rowH))
            strokeRect(CGRect(x: stageX, y: y, width: stageWidth, height: rowH))
            strokeRect(CGRect(x: doneX, y: y, width: initialsX - doneX, height: rowH))
            strokeRect(CGRect(x: initialsX, y: y, width: noteX - initialsX, height: rowH))
            strokeRect(CGRect(x: noteX, y: y, width: noteWidth, height: rowH))

            ("\(index + 1)" as NSString).draw(at: CGPoint(x: numX + 6, y: y + 4), withAttributes: rowAttrs)
            (task.title as NSString).draw(
                in: CGRect(x: stageX + 4, y: y + 4, width: stageWidth - 8, height: bounding.height),
                withAttributes: rowAttrs
            )
            ((task.isDone ? "☑" : "☐") as NSString).draw(at: CGPoint(x: doneX + 10, y: y + 4), withAttributes: rowAttrs)

            let noteText = task.completedAt.map(Format.shortDate.string) ?? task.notes
            (noteText as NSString).draw(
                in: CGRect(x: noteX + 4, y: y + 4, width: noteWidth - 8, height: bounding.height),
                withAttributes: rowAttrs
            )

            y += rowH
        }
        return y
    }

    private static func drawChecklistHeader(y: CGFloat) -> CGFloat {
        let headerHeight: CGFloat = 18
        let headerAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 9)]
        strokeRect(CGRect(x: numX, y: y, width: stageX - numX, height: headerHeight))
        strokeRect(CGRect(x: stageX, y: y, width: stageWidth, height: headerHeight))
        strokeRect(CGRect(x: doneX, y: y, width: initialsX - doneX, height: headerHeight))
        strokeRect(CGRect(x: initialsX, y: y, width: noteX - initialsX, height: headerHeight))
        strokeRect(CGRect(x: noteX, y: y, width: noteWidth, height: headerHeight))

        ("#" as NSString).draw(at: CGPoint(x: numX + 6, y: y + 4), withAttributes: headerAttrs)
        ("Workflow Stage" as NSString).draw(at: CGPoint(x: stageX + 4, y: y + 4), withAttributes: headerAttrs)
        ("Done" as NSString).draw(at: CGPoint(x: doneX + 4, y: y + 4), withAttributes: headerAttrs)
        ("Initials" as NSString).draw(at: CGPoint(x: initialsX + 4, y: y + 4), withAttributes: headerAttrs)
        ("Date / Notes" as NSString).draw(at: CGPoint(x: noteX + 4, y: y + 4), withAttributes: headerAttrs)
        return y + headerHeight
    }

    // MARK: Notes box

    private static func drawNotesBox(project: Project, y: CGFloat) {
        let height: CGFloat = 70
        let rect = CGRect(x: margin, y: y, width: contentWidth, height: height)
        strokeRect(rect)
        ("SPECIAL INSTRUCTIONS / NOTES" as NSString).draw(
            at: CGPoint(x: rect.minX + 6, y: rect.minY + 4),
            withAttributes: [.font: UIFont.boldSystemFont(ofSize: 8), .foregroundColor: UIColor.darkGray]
        )
        if !project.detail.isEmpty {
            (project.detail as NSString).draw(
                in: CGRect(x: rect.minX + 6, y: rect.minY + 16, width: rect.width - 12, height: rect.height - 20),
                withAttributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.black]
            )
        }
    }

    // MARK: Drawing primitives

    private static func strokeRect(_ rect: CGRect, lineWidth: CGFloat = 0.75) {
        let path = UIBezierPath(rect: rect)
        path.lineWidth = lineWidth
        UIColor.black.setStroke()
        path.stroke()
    }

    private static func strokeLine(from: CGPoint, to: CGPoint, lineWidth: CGFloat = 1) {
        let path = UIBezierPath()
        path.move(to: from)
        path.addLine(to: to)
        path.lineWidth = lineWidth
        UIColor.black.setStroke()
        path.stroke()
    }
}
