import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Plain-text clipboard access that works on iOS and macOS.
enum Clipboard {
    static var string: String? {
        get {
            #if canImport(UIKit)
            return UIPasteboard.general.string
            #else
            return NSPasteboard.general.string(forType: .string)
            #endif
        }
        set {
            #if canImport(UIKit)
            UIPasteboard.general.string = newValue
            #else
            NSPasteboard.general.clearContents()
            if let newValue { NSPasteboard.general.setString(newValue, forType: .string) }
            #endif
        }
    }
}
