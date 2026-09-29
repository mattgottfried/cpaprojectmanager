import Foundation
import CoreGraphics

/// Renders a merged letter (engagement letter, proposal) as a US Letter PDF: firm
/// letterhead, the body paginated paragraph by paragraph, and — for engagement letters
/// and proposals — an accept-and-sign block.
enum LetterPDF {
    private static let pageWidth: CGFloat = 612
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 64
    private static let bottomLimit: CGFloat = 792 - 64
    private static var contentWidth: CGFloat { pageWidth - margin * 2 }

    static func data(body: String, firmName: String, firmContact: String, signatureBlock: Bool, clientName: String) -> Data {
        PlatformPDF.data(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)) { context in
            context.beginPage()
            var y = drawLetterhead(firmName: firmName, firmContact: firmContact)

            let bodyFont = PlatformFont.systemFont(ofSize: 11)
            let paragraphs = body.components(separatedBy: "\n")
            for paragraph in paragraphs {
                if paragraph.trimmingCharacters(in: .whitespaces).isEmpty {
                    y += 8
                    continue
                }
                y = drawParagraph(paragraph, font: bodyFont, y: y, context: context)
            }

            if signatureBlock {
                y += 24
                if y + 110 > bottomLimit {
                    context.beginPage()
                    y = margin
                }
                drawSignatureBlock(clientName: clientName, y: y)
            }
        }
    }

    // MARK: Drawing

    private static func drawLetterhead(firmName: String, firmContact: String) -> CGFloat {
        var y = margin
        if !firmName.isEmpty {
            draw(firmName, font: .boldSystemFont(ofSize: 16), color: .black, at: CGPoint(x: margin, y: y))
            y += 22
        }
        if !firmContact.isEmpty {
            draw(firmContact, font: .systemFont(ofSize: 9), color: .darkGray, at: CGPoint(x: margin, y: y))
            y += 14
        }
        if y > margin {
            PlatformPDF.strokeLine(from: CGPoint(x: margin, y: y + 4), to: CGPoint(x: pageWidth - margin, y: y + 4), lineWidth: 0.75, color: .darkGray)
            y += 22
        }
        return y
    }

    /// Draws one paragraph, starting a new page when it doesn't fit; a paragraph taller
    /// than a page is split at word boundaries.
    private static func drawParagraph(_ text: String, font: PlatformFont, y startY: CGFloat, context: PDFRenderContext) -> CGFloat {
        var y = startY
        var remaining = text
        while !remaining.isEmpty {
            let available = bottomLimit - y
            let full = height(of: remaining, font: font)
            if full <= available {
                draw(remaining, font: font, color: .black, in: CGRect(x: margin, y: y, width: contentWidth, height: full))
                return y + full + 4
            }
            // Take as many words as fit on this page.
            let words = remaining.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
            var fit = 0
            var chunk = ""
            for (index, word) in words.enumerated() {
                let candidate = chunk.isEmpty ? word : chunk + " " + word
                if height(of: candidate, font: font) > available { break }
                chunk = candidate
                fit = index + 1
            }
            if fit == 0 {
                // Not even one line fits: start a fresh page (unless we're already at the top).
                if y <= margin + 1 { fit = 1; chunk = words[0] } else {
                    context.beginPage()
                    y = margin
                    continue
                }
            }
            let chunkHeight = height(of: chunk, font: font)
            draw(chunk, font: font, color: .black, in: CGRect(x: margin, y: y, width: contentWidth, height: chunkHeight))
            remaining = words.dropFirst(fit).joined(separator: " ")
            context.beginPage()
            y = margin
        }
        return y
    }

    private static func drawSignatureBlock(clientName: String, y startY: CGFloat) {
        var y = startY
        draw("Accepted and agreed:", font: .boldSystemFont(ofSize: 11), color: .black, at: CGPoint(x: margin, y: y))
        y += 40
        let lineEnd = margin + 260
        PlatformPDF.strokeLine(from: CGPoint(x: margin, y: y), to: CGPoint(x: lineEnd, y: y), lineWidth: 0.75, color: .black)
        PlatformPDF.strokeLine(from: CGPoint(x: lineEnd + 30, y: y), to: CGPoint(x: pageWidth - margin, y: y), lineWidth: 0.75, color: .black)
        y += 4
        draw(clientName, font: .systemFont(ofSize: 9), color: .darkGray, at: CGPoint(x: margin, y: y))
        draw("Date", font: .systemFont(ofSize: 9), color: .darkGray, at: CGPoint(x: lineEnd + 30, y: y))
    }

    // MARK: Text helpers

    private static func attributes(font: PlatformFont, color: PlatformColor) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: color]
    }

    private static func height(of text: String, font: PlatformFont) -> CGFloat {
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes(font: font, color: .black),
            context: nil
        )
        return ceil(rect.height)
    }

    private static func draw(_ text: String, font: PlatformFont, color: PlatformColor, at point: CGPoint) {
        (text as NSString).draw(at: point, withAttributes: attributes(font: font, color: color))
    }

    private static func draw(_ text: String, font: PlatformFont, color: PlatformColor, in rect: CGRect) {
        (text as NSString).draw(in: rect, withAttributes: attributes(font: font, color: color))
    }
}
