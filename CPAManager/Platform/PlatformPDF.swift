import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#else
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#endif

/// Minimal cross-platform PDF page renderer so `InvoicePDF` and `RoutingSheetPDF`
/// share one drawing code path on iOS and macOS.
///
/// Drawing uses top-left-origin coordinates on both platforms (UIKit's convention);
/// on macOS the context is flipped to match. Text is drawn with `NSString`'s
/// `draw(at:withAttributes:)` family, which exists in UIKit and AppKit alike.
final class PDFRenderContext {
    let bounds: CGRect
    private let beginPageHandler: () -> Void

    fileprivate init(bounds: CGRect, beginPage: @escaping () -> Void) {
        self.bounds = bounds
        self.beginPageHandler = beginPage
    }

    /// Starts a new page (call once before drawing, and again for each extra page).
    func beginPage() { beginPageHandler() }
}

enum PlatformPDF {
    static func data(bounds: CGRect, draw: (PDFRenderContext) -> Void) -> Data {
        #if canImport(UIKit)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { uiContext in
            let context = PDFRenderContext(bounds: bounds) { uiContext.beginPage() }
            draw(context)
        }
        #else
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var mediaBox = bounds
        guard let cg = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        var pageOpen = false
        let context = PDFRenderContext(bounds: bounds) {
            if pageOpen { NSGraphicsContext.restoreGraphicsState(); cg.endPDFPage() }
            cg.beginPDFPage(nil)
            // PDF's origin is bottom-left; flip so callers can use top-left coordinates.
            cg.translateBy(x: 0, y: bounds.height)
            cg.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
            pageOpen = true
        }
        draw(context)
        if pageOpen {
            NSGraphicsContext.restoreGraphicsState()
            cg.endPDFPage()
        }
        cg.closePDF()
        return data as Data
        #endif
    }

    /// The CGContext the current drawing goes to.
    static func currentContext() -> CGContext? {
        #if canImport(UIKit)
        return UIGraphicsGetCurrentContext()
        #else
        return NSGraphicsContext.current?.cgContext
        #endif
    }

    /// Fills `rect` with `color`.
    static func fill(_ rect: CGRect, color: PlatformColor) {
        color.setFill()
        #if canImport(UIKit)
        UIRectFill(rect)
        #else
        rect.fill()
        #endif
    }

    static func strokeRect(_ rect: CGRect, lineWidth: CGFloat, color: PlatformColor) {
        color.setStroke()
        #if canImport(UIKit)
        let path = UIBezierPath(rect: rect)
        #else
        let path = NSBezierPath(rect: rect)
        #endif
        path.lineWidth = lineWidth
        path.stroke()
    }

    static func strokeLine(from: CGPoint, to: CGPoint, lineWidth: CGFloat, color: PlatformColor) {
        color.setStroke()
        #if canImport(UIKit)
        let path = UIBezierPath()
        path.move(to: from)
        path.addLine(to: to)
        #else
        let path = NSBezierPath()
        path.move(to: from)
        path.line(to: to)
        #endif
        path.lineWidth = lineWidth
        path.stroke()
    }
}

extension PlatformFont {
    /// Italic system font (`NSFont` has no `italicSystemFont`).
    static func italicSystem(ofSize size: CGFloat) -> PlatformFont {
        #if canImport(UIKit)
        return UIFont.italicSystemFont(ofSize: size)
        #else
        return NSFontManager.shared.convert(NSFont.systemFont(ofSize: size), toHaveTrait: .italicFontMask)
        #endif
    }
}
