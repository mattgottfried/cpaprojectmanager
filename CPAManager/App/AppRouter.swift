import SwiftUI
import Observation

/// Every top-level destination. On iPhone the first four (plus More) are tabs; on
/// iPad and Mac they are all rows in the sidebar.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case today, inbox, clients, leads, work, deadlines, review
    case time, invoices, reports, templates, recurring, overview
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:     return "Today"
        case .inbox:     return "Inbox"
        case .clients:   return "Clients"
        case .leads:     return "Leads"
        case .work:      return "Work"
        case .deadlines: return "Deadlines"
        case .review:    return "Weekly Review"
        case .time:      return "Time & Billing"
        case .invoices:  return "Invoices"
        case .reports:   return "Reports"
        case .templates: return "Templates"
        case .recurring: return "Recurring Work"
        case .overview:  return "Firm Overview"
        case .settings:  return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .today:     return "sun.max.fill"
        case .inbox:     return "tray.fill"
        case .clients:   return "person.2.fill"
        case .leads:     return "funnel.fill"
        case .work:      return "checklist"
        case .deadlines: return "calendar"
        case .review:    return "checkmark.seal.fill"
        case .time:      return "clock.fill"
        case .invoices:  return "doc.text.image.fill"
        case .reports:   return "chart.bar.fill"
        case .templates: return "square.stack.3d.up.fill"
        case .recurring: return "arrow.triangle.2.circlepath"
        case .overview:  return "house.fill"
        case .settings:  return "gearshape.fill"
        }
    }

    /// Sidebar grouping.
    static let daily: [AppSection] = [.today, .inbox, .clients, .leads, .work, .deadlines, .review]
    static let practice: [AppSection] = [.time, .invoices, .reports, .templates, .recurring, .overview]
}

/// Which text field a keyboard shortcut / widget link wants focused once its screen
/// is showing.
enum CaptureFocus: Equatable {
    case newTask, inboxCapture
}

/// Shared navigation state so menu commands, keyboard shortcuts, widget links, and
/// the sidebar all drive the same selection.
@Observable
final class AppRouter {
    var section: AppSection = .today
    var pendingFocus: CaptureFocus?

    func go(to section: AppSection, focus: CaptureFocus? = nil) {
        self.section = section
        pendingFocus = focus
    }

    /// Handles `cpamanager://today`, `…://capture`, `…://inbox` (widget links).
    /// Unknown hosts (e.g. the QuickBooks OAuth callback) are ignored.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard url.scheme == "cpamanager" else { return false }
        switch url.host {
        case "today":   go(to: .today)
        case "capture": go(to: .today, focus: .newTask)
        case "inbox":   go(to: .inbox)
        case "review":  go(to: .review)
        case "leads":   go(to: .leads)
        default:        return false
        }
        return true
    }
}
