import SwiftUI
import Observation

/// Every top-level destination. On iPhone the first four (plus More) are tabs; on
/// iPad and Mac they are all rows in the sidebar.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case today, inbox, clients, leads, work, deadlines, review
    case time, invoices, recurringInvoices, expenses, reports, templates, recurring, overview
    case activity
    case extensions, quotes, feeSchedule, pipelines, letters, importData, dataHealth, syncHealth, backups, help
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
        case .recurringInvoices: return "Recurring Invoices"
        case .expenses:  return "Expenses"
        case .activity:  return "Activity"
        case .reports:   return "Reports"
        case .templates: return "Templates"
        case .recurring: return "Recurring Work"
        case .overview:  return "Firm Overview"
        case .extensions: return "Extensions"
        case .quotes:    return "Quotes"
        case .feeSchedule: return "Fee Schedule"
        case .pipelines: return "Pipelines"
        case .letters:   return "Letters & Emails"
        case .importData: return "Import from CSV"
        case .dataHealth: return "Data Health"
        case .syncHealth: return "Sync Health"
        case .backups:   return "Automatic Backups"
        case .help:      return "Help & Tips"
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
        case .recurringInvoices: return "arrow.triangle.2.circlepath.circle.fill"
        case .expenses:  return "creditcard.fill"
        case .activity:  return "clock.arrow.circlepath"
        case .reports:   return "chart.bar.fill"
        case .templates: return "square.stack.3d.up.fill"
        case .recurring: return "arrow.triangle.2.circlepath"
        case .overview:  return "house.fill"
        case .extensions: return "calendar.badge.clock"
        case .quotes:    return "doc.plaintext"
        case .feeSchedule: return "tag"
        case .pipelines: return "rectangle.split.3x1.fill"
        case .letters:   return "doc.richtext"
        case .importData: return "square.and.arrow.down"
        case .dataHealth: return "stethoscope"
        case .syncHealth: return "arrow.triangle.2.circlepath.icloud"
        case .backups:   return "externaldrive.fill.badge.timemachine"
        case .help:      return "questionmark.circle.fill"
        case .settings:  return "gearshape.fill"
        }
    }

    /// Sidebar grouping.
    static let daily: [AppSection] = [.today, .inbox, .clients, .leads, .work, .deadlines, .review, .activity]
    static let practice: [AppSection] = [.time, .invoices, .quotes, .recurringInvoices, .expenses, .reports, .templates, .recurring, .overview]
    /// Setup and upkeep screens that iPhone reaches through More.
    static let tools: [AppSection] = [.extensions, .pipelines, .feeSchedule, .letters, .importData, .dataHealth, .syncHealth, .backups, .help]
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
    /// A record to open once its screen is showing (Spotlight, Siri, notifications, search).
    var pendingLink: DeepLink?
    var showingQuickOpen = false
    /// Bumped by ⌘R to ask the shell to sync integrations right now.
    var refreshTick = 0

    func go(to section: AppSection, focus: CaptureFocus? = nil) {
        self.section = section
        pendingFocus = focus
    }

    /// Jumps to the screen that owns `link` and asks it to push the record.
    func open(_ link: DeepLink) {
        switch link {
        case .client:  section = .clients
        case .project: section = .work
        case .task:    section = .today
        case .invoice: section = .invoices
        }
        pendingLink = link
        pendingFocus = nil
    }

    /// Handles `cpamanager://today`, `…://capture`, `…://inbox` (widget links).
    /// Unknown hosts (e.g. the QuickBooks OAuth callback) are ignored.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard url.scheme == "cpamanager" else { return false }
        switch url.host {
        case "today":   go(to: .today)
        case "tasks":
            // The Tasks page lives inside Today (segmented switcher); remember the choice.
            UserDefaults.standard.set(TodayMode.tasks.rawValue, forKey: TodayMode.storageKey)
            go(to: .today)
        case "capture": go(to: .today, focus: .newTask)
        case "inbox":   go(to: .inbox)
        case "review":  go(to: .review)
        case "leads":   go(to: .leads)
        case "search":  showingQuickOpen = true
        case "activity": go(to: .activity)
        default:        return false
        }
        return true
    }
}

// MARK: - Per-window routing

/// Each window owns its own `AppRouter`; menu commands act on the focused window's.
private struct AppRouterFocusKey: FocusedValueKey {
    typealias Value = AppRouter
}

extension FocusedValues {
    var appRouter: AppRouter? {
        get { self[AppRouterFocusKey.self] }
        set { self[AppRouterFocusKey.self] = newValue }
    }
}
