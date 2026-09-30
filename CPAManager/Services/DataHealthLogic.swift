import Foundation

// Pure checks for problems that sync between devices can cause: two devices picking the
// same invoice number, default templates seeded twice, the same client added twice.

struct HealthInvoice: Equatable {
    var id: UUID
    var number: Int
    var createdAt: Date
    /// Already pushed to QuickBooks — renumbering would desync it, so it's report-only.
    var isSyncedToQuickBooks: Bool
}

struct HealthTemplate: Equatable {
    var id: UUID
    var name: String
    var taskTitles: [String]
    var createdAt: Date
    /// Something (recurring work) points at this template, so it can't be auto-removed.
    var isReferenced: Bool
}

struct HealthClient: Equatable {
    var id: UUID
    var name: String
    var email: String
}

struct HealthTimer: Equatable {
    var id: UUID
    var startedAt: Date
}

struct InvoiceRenumber: Equatable {
    var id: UUID
    var newNumber: Int
}

struct DataHealthReport: Equatable {
    /// Numbers used by more than one invoice.
    var duplicateInvoiceNumbers: [Int] = []
    /// Later duplicates that can be safely renumbered.
    var renumbers: [InvoiceRenumber] = []
    /// Duplicates that can't be renumbered automatically (already in QuickBooks).
    var unfixableInvoiceIDs: [UUID] = []
    /// Template copies safe to delete (identical name + steps, not in use).
    var duplicateTemplateIDs: [UUID] = []
    /// Client ids sharing an email with another client (report only — merging is a judgment call).
    var duplicateClientIDs: [UUID] = []
    var staleTimerIDs: [UUID] = []

    var isHealthy: Bool {
        duplicateInvoiceNumbers.isEmpty && duplicateTemplateIDs.isEmpty
            && duplicateClientIDs.isEmpty && staleTimerIDs.isEmpty
    }
}

enum DataHealth {
    static func report(
        invoices: [HealthInvoice],
        templates: [HealthTemplate],
        clients: [HealthClient],
        runningTimers: [HealthTimer],
        now: Date = .now,
        staleTimerHours: Double = 16
    ) -> DataHealthReport {
        var report = DataHealthReport()

        // Invoices: keep the oldest holder of each number, renumber the rest past the max.
        let grouped = Dictionary(grouping: invoices, by: \.number)
        var nextNumber = (invoices.map(\.number).max() ?? 1000) + 1
        for number in grouped.keys.sorted() {
            let group = (grouped[number] ?? []).sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            guard group.count > 1 else { continue }
            report.duplicateInvoiceNumbers.append(number)
            for invoice in group.dropFirst() {
                if invoice.isSyncedToQuickBooks {
                    report.unfixableInvoiceIDs.append(invoice.id)
                } else {
                    report.renumbers.append(InvoiceRenumber(id: invoice.id, newNumber: nextNumber))
                    nextNumber += 1
                }
            }
        }

        // Templates: identical name and steps; keep the oldest (or any that's referenced).
        let templateGroups = Dictionary(grouping: templates) {
            $0.name.lowercased() + "\u{1}" + $0.taskTitles.joined(separator: "\u{1}")
        }
        for key in templateGroups.keys.sorted() {
            let group = (templateGroups[key] ?? []).sorted {
                // Referenced copies sort first so they're the ones kept.
                if $0.isReferenced != $1.isReferenced { return $0.isReferenced }
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            guard group.count > 1 else { continue }
            report.duplicateTemplateIDs += group.dropFirst().filter { !$0.isReferenced }.map(\.id)
        }

        // Clients: same non-empty email.
        let byEmail = Dictionary(grouping: clients.filter { !$0.email.trimmingCharacters(in: .whitespaces).isEmpty }) {
            $0.email.lowercased().trimmingCharacters(in: .whitespaces)
        }
        for key in byEmail.keys.sorted() {
            let group = byEmail[key] ?? []
            if group.count > 1 { report.duplicateClientIDs += group.map(\.id) }
        }

        report.staleTimerIDs = runningTimers
            .filter { now.timeIntervalSince($0.startedAt) > staleTimerHours * 3600 }
            .map(\.id)
        return report
    }
}
