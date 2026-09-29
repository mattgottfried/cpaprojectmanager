import Foundation
import CoreGraphics

/// Renders a simple, one-page invoice PDF (US Letter) to a temporary file.
enum InvoicePDF {
    static func generate(invoice: Invoice, firmName: String) -> URL? {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 48
        let contentWidth = pageWidth - margin * 2

        let data = PlatformPDF.data(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)) { context in
            context.beginPage()
            var y: CGFloat = margin

            func draw(_ text: String, font: PlatformFont, color: PlatformColor = .black, width: CGFloat? = nil) {
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let boxWidth = width ?? contentWidth
                let bounding = (text as NSString).boundingRect(
                    with: CGSize(width: boxWidth, height: .greatestFiniteMagnitude),
                    options: .usesLineFragmentOrigin,
                    attributes: attrs,
                    context: nil
                )
                (text as NSString).draw(
                    in: CGRect(x: margin, y: y, width: boxWidth, height: bounding.height),
                    withAttributes: attrs
                )
                y += ceil(bounding.height) + 4
            }

            draw(firmName.isEmpty ? "Invoice" : firmName, font: .boldSystemFont(ofSize: 20))
            y += 6
            draw("Invoice \(invoice.displayNumber)", font: .boldSystemFont(ofSize: 15))
            draw("Issued \(Format.mediumDate.string(from: invoice.issueDate))", font: .systemFont(ofSize: 11), color: .darkGray)
            draw("Due \(Format.mediumDate.string(from: invoice.dueDate))", font: .systemFont(ofSize: 11), color: .darkGray)
            y += 14

            draw("Bill To", font: .boldSystemFont(ofSize: 11))
            draw(invoice.client?.displayName ?? "—", font: .systemFont(ofSize: 12))
            if let email = invoice.client?.email, !email.isEmpty {
                draw(email, font: .systemFont(ofSize: 11), color: .darkGray)
            }
            y += 16

            let col2X = pageWidth - margin - 220
            let col3X = pageWidth - margin - 140
            let col4X = pageWidth - margin - 70
            let descWidth = col2X - margin - 8

            let headerFont = PlatformFont.boldSystemFont(ofSize: 11)
            let headerAttrs: [NSAttributedString.Key: Any] = [.font: headerFont]
            ("Description" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: headerAttrs)
            ("Qty" as NSString).draw(at: CGPoint(x: col2X, y: y), withAttributes: headerAttrs)
            ("Rate" as NSString).draw(at: CGPoint(x: col3X, y: y), withAttributes: headerAttrs)
            ("Amount" as NSString).draw(at: CGPoint(x: col4X, y: y), withAttributes: headerAttrs)
            y += 16

            PlatformPDF.fill(CGRect(x: margin, y: y, width: contentWidth, height: 0.75), color: .lightGray)
            y += 8

            let rowFont = PlatformFont.systemFont(ofSize: 11)
            let rowAttrs: [NSAttributedString.Key: Any] = [.font: rowFont]
            for line in invoice.lineList {
                let bounding = (line.detail as NSString).boundingRect(
                    with: CGSize(width: descWidth, height: .greatestFiniteMagnitude),
                    options: .usesLineFragmentOrigin,
                    attributes: rowAttrs,
                    context: nil
                )
                (line.detail as NSString).draw(
                    in: CGRect(x: margin, y: y, width: descWidth, height: bounding.height),
                    withAttributes: rowAttrs
                )
                (String(format: "%.2f", line.quantity) as NSString).draw(at: CGPoint(x: col2X, y: y), withAttributes: rowAttrs)
                (Format.currency(line.rate) as NSString).draw(at: CGPoint(x: col3X, y: y), withAttributes: rowAttrs)
                (Format.currency(line.amount) as NSString).draw(at: CGPoint(x: col4X, y: y), withAttributes: rowAttrs)
                y += max(18, ceil(bounding.height) + 6)
            }

            y += 8
            PlatformPDF.fill(CGRect(x: margin, y: y, width: contentWidth, height: 0.75), color: .lightGray)
            y += 12

            let totalFont = PlatformFont.boldSystemFont(ofSize: 14)
            let totalAttrs: [NSAttributedString.Key: Any] = [.font: totalFont]
            ("Total" as NSString).draw(at: CGPoint(x: col3X, y: y), withAttributes: totalAttrs)
            (Format.currency(invoice.total) as NSString).draw(at: CGPoint(x: col4X, y: y), withAttributes: totalAttrs)
            y += 32

            if !invoice.notes.isEmpty {
                draw("Notes", font: .boldSystemFont(ofSize: 11))
                draw(invoice.notes, font: .systemFont(ofSize: 11), color: .darkGray)
            }
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(invoice.displayNumber)-\(UUID().uuidString.prefix(6)).pdf")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
