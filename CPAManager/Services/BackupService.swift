import Foundation
import SwiftData

/// A complete, human-readable JSON backup that doesn't depend on iCloud. Restoring is a
/// **merge**: records whose ID already exists are left alone, everything else is added
/// and re-linked. Nothing is ever deleted or overwritten by a restore.
struct BackupFile: Codable {
    static let currentVersion = 1

    var version = BackupFile.currentVersion
    var createdAt = Date.now

    var clients: [ClientRecord] = []
    var projects: [ProjectRecord] = []
    var tasks: [TaskRecord] = []
    var timeEntries: [TimeRecord] = []
    var documents: [DocumentRecord] = []
    var templates: [TemplateRecord] = []
    var templateTasks: [TemplateTaskRecord] = []
    var engagements: [EngagementRecord] = []
    var invoices: [InvoiceRecord] = []
    var invoiceLines: [InvoiceLineRecord] = []
    var payments: [PaymentRecord] = []
    var inbox: [InboxRecord] = []
    var interactions: [InteractionRecord] = []
    var savedFilters: [SavedFilterRecord] = []
    var documentRequests: [DocumentRequestRecord] = []
    var recurringInvoices: [RecurringInvoiceRecord] = []
    var expenses: [ExpenseRecord] = []
    // Added in batch 5. Optional so backups made by earlier builds still decode.
    var pipelines: [PipelineRecord]? = nil
    var letterTemplates: [LetterTemplateRecord]? = nil
    var emailTemplates: [EmailTemplateRecord]? = nil
    // Added in batch 6.
    var feeItems: [FeeItemRecord]? = nil
    var quotes: [QuoteRecord]? = nil
    // Added in batch 7.
    var builtInStages: [BuiltInStageRecord]? = nil

    // MARK: Records (one per model; relationships are stored as IDs)

    struct ClientRecord: Codable {
        var id: UUID; var name: String; var company: String; var entityTypeRaw: String; var statusRaw: String
        var email: String; var phone: String; var notes: String; var createdAt: Date; var qboCustomerId: String
        var tagsRaw: String; var followUpDate: Date?; var leadStageRaw: String; var leadValue: Double
        var extensionYearsRaw: String
        // Batch 5 (optional for older backups).
        var birthday: Date? = nil; var anniversary: Date? = nil
        var birthdayAckYear: Int? = nil; var anniversaryAckYear: Int? = nil
        // Batch 6.
        var hourlyRateOverride: Double? = nil; var isFlatFee: Bool? = nil
        // Batch 7.
        var driveFolderID: String? = nil; var driveFolderName: String? = nil
    }
    struct ProjectRecord: Codable {
        var id: UUID; var title: String; var detail: String; var statusRaw: String; var serviceTypeRaw: String
        var priorityRaw: String; var startDate: Date?; var dueDate: Date?; var completedAt: Date?; var taxYear: Int
        var templateName: String?; var createdAt: Date; var receivedDate: Date?; var nextAction: String
        var holdReasonRaw: String; var holdDetail: String; var holdResumeStatusRaw: String; var clientID: UUID?
        var pipelineID: UUID? = nil; var stageKey: String? = nil
        // Batch 7.
        var invoiceID: UUID? = nil; var billingStateRaw: String? = nil
        var driveFolderID: String? = nil; var driveFolderName: String? = nil
        // Batch 10: stage clock.
        var stageEnteredAt: Date? = nil; var stageEnteredKey: String? = nil
    }
    struct TaskRecord: Codable {
        var id: UUID; var title: String; var notes: String; var isDone: Bool; var dueDate: Date?; var sortIndex: Int
        var completedAt: Date?; var createdAt: Date; var isNextAction: Bool; var snoozedUntil: Date?
        var repeatRuleRaw: String; var projectID: UUID?; var clientID: UUID?
        // Batch 6.
        var checklist: String? = nil; var blockedByID: UUID? = nil; var waitingOn: String? = nil
        var dueInDaysAfterBlocker: Int? = nil
        // Batch 8.
        var priorityRaw: String? = nil; var statusRaw: String? = nil; var startDate: Date? = nil
        var stageKey: String? = nil
    }
    struct TimeRecord: Codable {
        var id: UUID; var startedAt: Date; var endedAt: Date?; var notes: String; var isBillable: Bool
        var hourlyRate: Double; var projectTitle: String; var clientName: String; var createdAt: Date
        var invoiceID: UUID?; var projectID: UUID?
        // Batch 10.
        var taskID: UUID? = nil
    }
    struct DocumentRecord: Codable {
        var id: UUID; var filename: String; var fileExtension: String; var data: Data?; var createdAt: Date
        var clientID: UUID?; var projectID: UUID?
        // Batch 6.
        var signatureStatusRaw: String? = nil; var signatureSentAt: Date? = nil; var signedAt: Date? = nil
        // Batch 7: a file that lives in Google Drive.
        var driveFileID: String? = nil; var driveURL: String? = nil; var driveMimeType: String? = nil
    }
    struct TemplateRecord: Codable {
        var id: UUID; var name: String; var detail: String; var serviceTypeRaw: String
        var defaultDurationDays: Int; var createdAt: Date
        var pipelineID: UUID? = nil; var startStageKey: String? = nil
    }
    struct TemplateTaskRecord: Codable {
        var id: UUID; var title: String; var sortIndex: Int; var dayOffset: Int; var templateID: UUID?
    }
    struct EngagementRecord: Codable {
        var id: UUID; var name: String; var frequencyRaw: String; var serviceTypeRaw: String; var isActive: Bool
        var nextDueDate: Date; var leadTimeDays: Int; var lastGeneratedDueDate: Date?; var adjustForWeekends: Bool
        var createdAt: Date; var clientID: UUID?; var templateID: UUID?
        var endDate: Date? = nil; var namingPattern: String? = nil
    }
    struct InvoiceRecord: Codable {
        var id: UUID; var number: Int; var issueDate: Date; var dueDate: Date; var statusRaw: String; var notes: String
        var qboId: String; var qboSyncStateRaw: String; var qboSyncError: String; var createdAt: Date; var clientID: UUID?
    }
    struct InvoiceLineRecord: Codable {
        var id: UUID; var detail: String; var quantity: Double; var rate: Double; var sortIndex: Int
        var timeEntryID: UUID?; var invoiceID: UUID?
    }
    struct PaymentRecord: Codable {
        var id: UUID; var amount: Double; var date: Date; var methodRaw: String; var note: String
        var createdAt: Date; var invoiceID: UUID?
    }
    struct InboxRecord: Codable {
        var id: UUID; var text: String; var sourceRaw: String; var createdAt: Date; var isProcessed: Bool
        var processedAt: Date?; var dedupeKey: String; var externalID: String; var link: String; var clientID: UUID?
    }
    struct InteractionRecord: Codable {
        var id: UUID; var kindRaw: String; var summary: String; var occurredAt: Date; var createdAt: Date; var clientID: UUID?
    }
    struct SavedFilterRecord: Codable {
        var id: UUID; var name: String; var statusRaw: String; var entityTypeRaw: String; var tag: String
        var onlyWithOpenWork: Bool; var createdAt: Date
    }
    struct DocumentRequestRecord: Codable {
        var id: UUID; var title: String; var notes: String; var requestedAt: Date; var dueDate: Date?
        var receivedAt: Date?; var createdAt: Date; var clientID: UUID?; var projectID: UUID?
    }
    struct RecurringInvoiceRecord: Codable {
        var id: UUID; var name: String; var frequencyRaw: String; var nextIssueDate: Date; var termsDays: Int
        var isActive: Bool; var notes: String; var linesData: Data; var lastGeneratedAt: Date?; var createdAt: Date
        var clientID: UUID?
    }
    struct ExpenseRecord: Codable {
        var id: UUID; var amount: Double; var date: Date; var categoryRaw: String; var vendor: String; var note: String
        var deductiblePercent: Int; var receiptData: Data?; var receiptExtension: String; var createdAt: Date
        var clientID: UUID?
    }

    struct BuiltInStageRecord: Codable {
        var id: UUID; var serviceTypeRaw: String; var stageKey: String; var automationData: Data; var updatedAt: Date
    }

    struct FeeItemRecord: Codable {
        var id: UUID; var name: String; var detail: String; var unitPrice: Double; var isHourly: Bool
        var sortIndex: Int; var createdAt: Date
    }
    struct QuoteRecord: Codable {
        var id: UUID; var number: Int; var statusRaw: String; var issueDate: Date; var validUntil: Date?
        var notes: String; var linesData: Data; var invoiceID: UUID?; var createdAt: Date; var clientID: UUID?
    }
    struct PipelineRecord: Codable {
        var id: UUID; var name: String; var systemImage: String; var sortIndex: Int
        var stagesData: Data; var createdAt: Date
    }
    struct LetterTemplateRecord: Codable {
        var id: UUID; var name: String; var kindRaw: String; var body: String; var createdAt: Date
    }
    struct EmailTemplateRecord: Codable {
        var id: UUID; var name: String; var subject: String; var body: String; var createdAt: Date
    }

    /// One line per record type, for the restore preview.
    var summary: [(label: String, count: Int)] {
        var rows: [(label: String, count: Int)] = []
        func add(_ label: String, _ count: Int) { if count > 0 { rows.append((label: label, count: count)) } }
        add("Clients", clients.count)
        add("Projects", projects.count)
        add("Tasks", tasks.count)
        add("Time entries", timeEntries.count)
        add("Documents", documents.count)
        add("Templates", templates.count)
        add("Recurring work", engagements.count)
        add("Invoices", invoices.count)
        add("Payments", payments.count)
        add("Inbox items", inbox.count)
        add("Activity entries", interactions.count)
        add("Saved filters", savedFilters.count)
        add("Document requests", documentRequests.count)
        add("Recurring invoices", recurringInvoices.count)
        add("Expenses", expenses.count)
        add("Pipelines", pipelines?.count ?? 0)
        add("Letter templates", letterTemplates?.count ?? 0)
        add("Email templates", emailTemplates?.count ?? 0)
        add("Fee items", feeItems?.count ?? 0)
        add("Quotes", quotes?.count ?? 0)
        add("Built-in stage tasks", builtInStages?.count ?? 0)
        return rows
    }

    var totalRecords: Int {
        clients.count + projects.count + tasks.count + timeEntries.count + documents.count + templates.count
            + templateTasks.count + engagements.count + invoices.count + invoiceLines.count + payments.count
            + inbox.count + interactions.count + savedFilters.count + documentRequests.count
            + recurringInvoices.count + expenses.count
            + (pipelines?.count ?? 0) + (letterTemplates?.count ?? 0) + (emailTemplates?.count ?? 0)
            + (feeItems?.count ?? 0) + (quotes?.count ?? 0) + (builtInStages?.count ?? 0)
    }
}

enum BackupService {
    enum BackupError: LocalizedError {
        case unreadable
        case newerVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return "That file isn't a CPA Manager backup."
            case .newerVersion(let v):
                return "This backup was made by a newer version of the app (format \(v)). Update the app and try again."
            }
        }
    }

    // MARK: Encode / decode

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(BackupFile.self, from: data) else { throw BackupError.unreadable }
        if file.version > BackupFile.currentVersion { throw BackupError.newerVersion(file.version) }
        return file
    }

    // MARK: Export

    /// `includeFiles: false` leaves out document, receipt, and other binary payloads
    /// (much smaller; everything else is still backed up).
    @MainActor
    static func export(context: ModelContext, includeFiles: Bool = true) -> BackupFile {
        func all<T: PersistentModel>(_ type: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }

        var file = BackupFile()
        file.clients = all(Client.self).map { c -> BackupFile.ClientRecord in
            BackupFile.ClientRecord(id: c.id, name: c.name, company: c.company, entityTypeRaw: c.entityTypeRaw, statusRaw: c.statusRaw,
                  email: c.email, phone: c.phone, notes: c.notes, createdAt: c.createdAt, qboCustomerId: c.qboCustomerId,
                  tagsRaw: c.tagsRaw, followUpDate: c.followUpDate, leadStageRaw: c.leadStageRaw, leadValue: c.leadValue,
                  extensionYearsRaw: c.extensionYearsRaw,
                  birthday: c.birthday, anniversary: c.anniversary,
                  birthdayAckYear: c.birthdayAckYear, anniversaryAckYear: c.anniversaryAckYear,
                  hourlyRateOverride: c.hourlyRateOverride, isFlatFee: c.isFlatFee,
                  driveFolderID: c.driveFolderID, driveFolderName: c.driveFolderName)
        }
        file.projects = all(Project.self).map { p in
            BackupFile.ProjectRecord(id: p.id, title: p.title, detail: p.detail, statusRaw: p.statusRaw, serviceTypeRaw: p.serviceTypeRaw,
                  priorityRaw: p.priorityRaw, startDate: p.startDate, dueDate: p.dueDate, completedAt: p.completedAt,
                  taxYear: p.taxYear, templateName: p.templateName, createdAt: p.createdAt, receivedDate: p.receivedDate,
                  nextAction: p.nextAction, holdReasonRaw: p.holdReasonRaw, holdDetail: p.holdDetail,
                  holdResumeStatusRaw: p.holdResumeStatusRaw, clientID: p.client?.id,
                  pipelineID: p.pipelineID, stageKey: p.stageKey,
                  invoiceID: p.invoiceID, billingStateRaw: p.billingStateRaw,
                  driveFolderID: p.driveFolderID, driveFolderName: p.driveFolderName,
                  stageEnteredAt: p.stageEnteredAt, stageEnteredKey: p.stageEnteredKey)
        }
        file.tasks = all(TaskItem.self).map { t in
            BackupFile.TaskRecord(id: t.id, title: t.title, notes: t.notes, isDone: t.isDone, dueDate: t.dueDate, sortIndex: t.sortIndex,
                  completedAt: t.completedAt, createdAt: t.createdAt, isNextAction: t.isNextAction,
                  snoozedUntil: t.snoozedUntil, repeatRuleRaw: t.repeatRuleRaw, projectID: t.project?.id, clientID: t.client?.id,
                  checklist: t.checklist, blockedByID: t.blockedByID, waitingOn: t.waitingOn,
                  dueInDaysAfterBlocker: t.dueInDaysAfterBlocker,
                  priorityRaw: t.priorityRaw, statusRaw: t.statusRaw, startDate: t.startDate, stageKey: t.stageKey)
        }
        file.timeEntries = all(TimeEntry.self).map { t in
            BackupFile.TimeRecord(id: t.id, startedAt: t.startedAt, endedAt: t.endedAt, notes: t.notes, isBillable: t.isBillable,
                  hourlyRate: t.hourlyRate, projectTitle: t.projectTitle, clientName: t.clientName,
                  createdAt: t.createdAt, invoiceID: t.invoiceID, projectID: t.project?.id, taskID: t.taskID)
        }
        file.documents = all(Document.self).map { d in
            BackupFile.DocumentRecord(id: d.id, filename: d.filename, fileExtension: d.fileExtension, data: includeFiles && !d.data.isEmpty ? d.data : nil,
                  createdAt: d.createdAt, clientID: d.client?.id, projectID: d.project?.id,
                  signatureStatusRaw: d.signatureStatusRaw, signatureSentAt: d.signatureSentAt, signedAt: d.signedAt,
                  driveFileID: d.driveFileID, driveURL: d.driveURL, driveMimeType: d.driveMimeType)
        }
        file.templates = all(WorkflowTemplate.self).map { t in
            BackupFile.TemplateRecord(id: t.id, name: t.name, detail: t.detail, serviceTypeRaw: t.serviceTypeRaw,
                  defaultDurationDays: t.defaultDurationDays, createdAt: t.createdAt,
                  pipelineID: t.pipelineID, startStageKey: t.startStageKey)
        }
        file.templateTasks = all(TemplateTask.self).map { t in
            BackupFile.TemplateTaskRecord(id: t.id, title: t.title, sortIndex: t.sortIndex, dayOffset: t.dayOffset, templateID: t.template?.id)
        }
        file.engagements = all(RecurringEngagement.self).map { e in
            BackupFile.EngagementRecord(id: e.id, name: e.name, frequencyRaw: e.frequencyRaw, serviceTypeRaw: e.serviceTypeRaw,
                  isActive: e.isActive, nextDueDate: e.nextDueDate, leadTimeDays: e.leadTimeDays,
                  lastGeneratedDueDate: e.lastGeneratedDueDate, adjustForWeekends: e.adjustForWeekends,
                  createdAt: e.createdAt, clientID: e.client?.id, templateID: e.template?.id,
                  endDate: e.endDate, namingPattern: e.namingPattern)
        }
        file.invoices = all(Invoice.self).map { i in
            BackupFile.InvoiceRecord(id: i.id, number: i.number, issueDate: i.issueDate, dueDate: i.dueDate, statusRaw: i.statusRaw,
                  notes: i.notes, qboId: i.qboId, qboSyncStateRaw: i.qboSyncStateRaw, qboSyncError: i.qboSyncError,
                  createdAt: i.createdAt, clientID: i.client?.id)
        }
        file.invoiceLines = all(InvoiceLine.self).map { l in
            BackupFile.InvoiceLineRecord(id: l.id, detail: l.detail, quantity: l.quantity, rate: l.rate, sortIndex: l.sortIndex,
                  timeEntryID: l.timeEntryID, invoiceID: l.invoice?.id)
        }
        file.payments = all(Payment.self).map { p in
            BackupFile.PaymentRecord(id: p.id, amount: p.amount, date: p.date, methodRaw: p.methodRaw, note: p.note,
                  createdAt: p.createdAt, invoiceID: p.invoice?.id)
        }
        file.inbox = all(InboxItem.self).map { i in
            BackupFile.InboxRecord(id: i.id, text: i.text, sourceRaw: i.sourceRaw, createdAt: i.createdAt, isProcessed: i.isProcessed,
                  processedAt: i.processedAt, dedupeKey: i.dedupeKey, externalID: i.externalID, link: i.link,
                  clientID: i.client?.id)
        }
        file.interactions = all(Interaction.self).map { i in
            BackupFile.InteractionRecord(id: i.id, kindRaw: i.kindRaw, summary: i.summary, occurredAt: i.occurredAt,
                  createdAt: i.createdAt, clientID: i.client?.id)
        }
        file.savedFilters = all(SavedClientFilter.self).map { f in
            BackupFile.SavedFilterRecord(id: f.id, name: f.name, statusRaw: f.statusRaw, entityTypeRaw: f.entityTypeRaw, tag: f.tag,
                  onlyWithOpenWork: f.onlyWithOpenWork, createdAt: f.createdAt)
        }
        file.documentRequests = all(DocumentRequest.self).map { r in
            BackupFile.DocumentRequestRecord(id: r.id, title: r.title, notes: r.notes, requestedAt: r.requestedAt, dueDate: r.dueDate,
                  receivedAt: r.receivedAt, createdAt: r.createdAt, clientID: r.client?.id, projectID: r.project?.id)
        }
        file.recurringInvoices = all(RecurringInvoice.self).map { r in
            BackupFile.RecurringInvoiceRecord(id: r.id, name: r.name, frequencyRaw: r.frequencyRaw, nextIssueDate: r.nextIssueDate,
                  termsDays: r.termsDays, isActive: r.isActive, notes: r.notes, linesData: r.linesData,
                  lastGeneratedAt: r.lastGeneratedAt, createdAt: r.createdAt, clientID: r.client?.id)
        }
        file.expenses = all(Expense.self).map { e in
            BackupFile.ExpenseRecord(id: e.id, amount: e.amount, date: e.date, categoryRaw: e.categoryRaw, vendor: e.vendor, note: e.note,
                  deductiblePercent: e.deductiblePercent, receiptData: includeFiles && !e.receiptData.isEmpty ? e.receiptData : nil,
                  receiptExtension: e.receiptExtension, createdAt: e.createdAt, clientID: e.client?.id)
        }
        file.pipelines = all(Pipeline.self).map { p in
            BackupFile.PipelineRecord(id: p.id, name: p.name, systemImage: p.systemImage, sortIndex: p.sortIndex,
                  stagesData: p.stagesData, createdAt: p.createdAt)
        }
        file.letterTemplates = all(LetterTemplate.self).map { l in
            BackupFile.LetterTemplateRecord(id: l.id, name: l.name, kindRaw: l.kindRaw, body: l.body, createdAt: l.createdAt)
        }
        file.feeItems = all(FeeItem.self).map { f in
            BackupFile.FeeItemRecord(id: f.id, name: f.name, detail: f.detail, unitPrice: f.unitPrice, isHourly: f.isHourly,
                  sortIndex: f.sortIndex, createdAt: f.createdAt)
        }
        file.builtInStages = all(BuiltInStageSetup.self).map { b in
            BackupFile.BuiltInStageRecord(id: b.id, serviceTypeRaw: b.serviceTypeRaw, stageKey: b.stageKey,
                  automationData: b.automationData, updatedAt: b.updatedAt)
        }
        file.quotes = all(Quote.self).map { q in
            BackupFile.QuoteRecord(id: q.id, number: q.number, statusRaw: q.statusRaw, issueDate: q.issueDate, validUntil: q.validUntil,
                  notes: q.notes, linesData: q.linesData, invoiceID: q.invoiceID, createdAt: q.createdAt, clientID: q.client?.id)
        }
        file.emailTemplates = all(EmailTemplate.self).map { e in
            BackupFile.EmailTemplateRecord(id: e.id, name: e.name, subject: e.subject, body: e.body, createdAt: e.createdAt)
        }
        return file
    }

    @MainActor
    static func exportData(context: ModelContext, includeFiles: Bool = true) throws -> Data {
        try encoder().encode(export(context: context, includeFiles: includeFiles))
    }

    @MainActor
    static func exportFile(context: ModelContext, includeFiles: Bool, now: Date = .now) -> URL? {
        guard let data = try? exportData(context: context, includeFiles: includeFiles) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CPA Manager Backup \(CSVWriter.date(now)).json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    // MARK: Restore (merge)

    struct RestoreResult: Equatable {
        var inserted = 0
        var skippedExisting = 0
        /// Existing records rewritten from the file (only with `overwrite: true`).
        var updated = 0
    }

    @MainActor
    @discardableResult
    static func restore(_ file: BackupFile, into context: ModelContext, overwrite: Bool = false) -> RestoreResult {
        var result = RestoreResult()

        func existing<T: PersistentModel>(_ type: T.Type, id: KeyPath<T, UUID>) -> [UUID: T] {
            let models = (try? context.fetch(FetchDescriptor<T>())) ?? []
            return Dictionary(models.map { ($0[keyPath: id], $0) }, uniquingKeysWith: { first, _ in first })
        }

        /// Inserts records that aren't present yet and returns the full id → model map
        /// (existing + new) so later records can link to either. With `overwrite`, records
        /// that already exist are rewritten from the file instead of skipped (used by sync).
        func merge<T: PersistentModel, R>(
            _ type: T.Type, id: KeyPath<T, UUID>, records: [R], recordID: (R) -> UUID,
            make: () -> T, fill: (R, T) -> Void, link: (R, T) -> Void
        ) -> [UUID: T] {
            var map = existing(type, id: id)
            for record in records {
                if let model = map[recordID(record)] {
                    if overwrite {
                        fill(record, model)
                        link(record, model)
                        result.updated += 1
                    } else {
                        result.skippedExisting += 1
                    }
                    continue
                }
                let model = make()
                context.insert(model)
                fill(record, model)
                link(record, model)
                map[recordID(record)] = model
                result.inserted += 1
            }
            return map
        }

        let clients = merge(Client.self, id: \.id, records: file.clients, recordID: { $0.id }, make: { Client() }, fill: { r, c in
            c.id = r.id; c.name = r.name; c.company = r.company; c.notes = r.notes
            c.entityTypeRaw = r.entityTypeRaw; c.statusRaw = r.statusRaw; c.email = r.email; c.phone = r.phone
            c.createdAt = r.createdAt; c.qboCustomerId = r.qboCustomerId; c.tagsRaw = r.tagsRaw
            c.followUpDate = r.followUpDate; c.leadStageRaw = r.leadStageRaw; c.leadValue = r.leadValue
            c.extensionYearsRaw = r.extensionYearsRaw
            c.birthday = r.birthday; c.anniversary = r.anniversary
            c.birthdayAckYear = r.birthdayAckYear ?? 0; c.anniversaryAckYear = r.anniversaryAckYear ?? 0
            c.hourlyRateOverride = r.hourlyRateOverride ?? 0; c.isFlatFee = r.isFlatFee ?? false
            c.driveFolderID = r.driveFolderID ?? ""; c.driveFolderName = r.driveFolderName ?? ""
        }, link: { _, _ in })

        let projects = merge(Project.self, id: \.id, records: file.projects, recordID: { $0.id }, make: { Project() }, fill: { r, p in
            p.id = r.id; p.title = r.title; p.detail = r.detail
            p.statusRaw = r.statusRaw; p.serviceTypeRaw = r.serviceTypeRaw; p.priorityRaw = r.priorityRaw
            p.startDate = r.startDate; p.dueDate = r.dueDate; p.completedAt = r.completedAt; p.taxYear = r.taxYear
            p.templateName = r.templateName; p.createdAt = r.createdAt; p.receivedDate = r.receivedDate
            p.nextAction = r.nextAction; p.holdReasonRaw = r.holdReasonRaw; p.holdDetail = r.holdDetail
            p.holdResumeStatusRaw = r.holdResumeStatusRaw
            p.pipelineID = r.pipelineID; p.stageKey = r.stageKey ?? ""
            p.invoiceID = r.invoiceID; p.billingStateRaw = r.billingStateRaw ?? ""
            p.driveFolderID = r.driveFolderID ?? ""; p.driveFolderName = r.driveFolderName ?? ""
            p.stageEnteredAt = r.stageEnteredAt; p.stageEnteredKey = r.stageEnteredKey ?? ""
        }, link: { r, p in p.client = r.clientID.flatMap { clients[$0] } })

        _ = merge(TaskItem.self, id: \.id, records: file.tasks, recordID: { $0.id }, make: { TaskItem() }, fill: { r, t in
            t.id = r.id; t.title = r.title; t.notes = r.notes
            t.isDone = r.isDone; t.dueDate = r.dueDate; t.sortIndex = r.sortIndex
            t.completedAt = r.completedAt; t.createdAt = r.createdAt; t.isNextAction = r.isNextAction
            t.snoozedUntil = r.snoozedUntil; t.repeatRuleRaw = r.repeatRuleRaw
            t.checklist = r.checklist ?? ""; t.blockedByID = r.blockedByID; t.waitingOn = r.waitingOn ?? ""
            t.dueInDaysAfterBlocker = r.dueInDaysAfterBlocker
            t.priorityRaw = r.priorityRaw ?? ""; t.statusRaw = r.statusRaw ?? ""; t.startDate = r.startDate
            t.stageKey = r.stageKey ?? ""
        }, link: { r, t in
            t.project = r.projectID.flatMap { projects[$0] }
            t.client = r.clientID.flatMap { clients[$0] }
        })

        _ = merge(TimeEntry.self, id: \.id, records: file.timeEntries, recordID: { $0.id }, make: { TimeEntry() }, fill: { r, t in
            t.id = r.id; t.startedAt = r.startedAt; t.endedAt = r.endedAt; t.notes = r.notes
            t.isBillable = r.isBillable; t.hourlyRate = r.hourlyRate
            t.projectTitle = r.projectTitle; t.clientName = r.clientName
            t.createdAt = r.createdAt; t.invoiceID = r.invoiceID; t.taskID = r.taskID
        }, link: { r, t in t.project = r.projectID.flatMap { projects[$0] } })

        _ = merge(Document.self, id: \.id, records: file.documents, recordID: { $0.id }, make: { Document() }, fill: { r, d in
            d.id = r.id; d.filename = r.filename; d.fileExtension = r.fileExtension
            // A record without the file (backup without files, or too large to sync) never
            // wipes a copy this device already has.
            if let data = r.data { d.data = data }
            d.createdAt = r.createdAt
            d.signatureStatusRaw = r.signatureStatusRaw ?? ""; d.signatureSentAt = r.signatureSentAt; d.signedAt = r.signedAt
            d.driveFileID = r.driveFileID ?? ""; d.driveURL = r.driveURL ?? ""; d.driveMimeType = r.driveMimeType ?? ""
        }, link: { r, d in
            d.client = r.clientID.flatMap { clients[$0] }
            d.project = r.projectID.flatMap { projects[$0] }
        })

        let templates = merge(WorkflowTemplate.self, id: \.id, records: file.templates, recordID: { $0.id }, make: { WorkflowTemplate() }, fill: { r, t in
            t.id = r.id; t.name = r.name; t.detail = r.detail
            t.serviceTypeRaw = r.serviceTypeRaw; t.defaultDurationDays = r.defaultDurationDays
            t.createdAt = r.createdAt
            t.pipelineID = r.pipelineID; t.startStageKey = r.startStageKey ?? ""
        }, link: { _, _ in })

        _ = merge(TemplateTask.self, id: \.id, records: file.templateTasks, recordID: { $0.id }, make: { TemplateTask() }, fill: { r, t in
            t.id = r.id; t.title = r.title; t.sortIndex = r.sortIndex; t.dayOffset = r.dayOffset
        }, link: { r, t in t.template = r.templateID.flatMap { templates[$0] } })

        _ = merge(RecurringEngagement.self, id: \.id, records: file.engagements, recordID: { $0.id }, make: { RecurringEngagement() }, fill: { r, e in
            e.id = r.id; e.name = r.name; e.isActive = r.isActive; e.nextDueDate = r.nextDueDate
            e.leadTimeDays = r.leadTimeDays; e.adjustForWeekends = r.adjustForWeekends
            e.frequencyRaw = r.frequencyRaw; e.serviceTypeRaw = r.serviceTypeRaw
            e.lastGeneratedDueDate = r.lastGeneratedDueDate; e.createdAt = r.createdAt
            e.endDate = r.endDate; e.namingPattern = r.namingPattern ?? ""
        }, link: { r, e in
            e.client = r.clientID.flatMap { clients[$0] }
            e.template = r.templateID.flatMap { templates[$0] }
        })

        let invoices = merge(Invoice.self, id: \.id, records: file.invoices, recordID: { $0.id }, make: { Invoice() }, fill: { r, i in
            i.id = r.id; i.number = r.number; i.issueDate = r.issueDate; i.dueDate = r.dueDate; i.notes = r.notes
            i.statusRaw = r.statusRaw; i.qboId = r.qboId; i.qboSyncStateRaw = r.qboSyncStateRaw
            i.qboSyncError = r.qboSyncError; i.createdAt = r.createdAt
        }, link: { r, i in i.client = r.clientID.flatMap { clients[$0] } })

        _ = merge(InvoiceLine.self, id: \.id, records: file.invoiceLines, recordID: { $0.id }, make: { InvoiceLine() }, fill: { r, l in
            l.id = r.id; l.detail = r.detail; l.quantity = r.quantity; l.rate = r.rate
            l.sortIndex = r.sortIndex; l.timeEntryID = r.timeEntryID
        }, link: { r, l in l.invoice = r.invoiceID.flatMap { invoices[$0] } })

        _ = merge(Payment.self, id: \.id, records: file.payments, recordID: { $0.id }, make: { Payment() }, fill: { r, p in
            p.id = r.id; p.amount = r.amount; p.date = r.date; p.note = r.note
            p.methodRaw = r.methodRaw; p.createdAt = r.createdAt
        }, link: { r, p in p.invoice = r.invoiceID.flatMap { invoices[$0] } })

        _ = merge(InboxItem.self, id: \.id, records: file.inbox, recordID: { $0.id }, make: { InboxItem() }, fill: { r, i in
            i.id = r.id; i.text = r.text
            i.sourceRaw = r.sourceRaw; i.createdAt = r.createdAt; i.isProcessed = r.isProcessed
            i.processedAt = r.processedAt; i.dedupeKey = r.dedupeKey; i.externalID = r.externalID; i.link = r.link
        }, link: { r, i in i.client = r.clientID.flatMap { clients[$0] } })

        _ = merge(Interaction.self, id: \.id, records: file.interactions, recordID: { $0.id }, make: { Interaction() }, fill: { r, i in
            i.id = r.id; i.summary = r.summary; i.occurredAt = r.occurredAt
            i.kindRaw = r.kindRaw; i.createdAt = r.createdAt
        }, link: { r, i in i.client = r.clientID.flatMap { clients[$0] } })

        _ = merge(SavedClientFilter.self, id: \.id, records: file.savedFilters, recordID: { $0.id }, make: { SavedClientFilter() }, fill: { r, f in
            f.id = r.id; f.name = r.name
            f.statusRaw = r.statusRaw; f.entityTypeRaw = r.entityTypeRaw; f.tag = r.tag
            f.onlyWithOpenWork = r.onlyWithOpenWork; f.createdAt = r.createdAt
        }, link: { _, _ in })

        _ = merge(DocumentRequest.self, id: \.id, records: file.documentRequests, recordID: { $0.id }, make: { DocumentRequest() }, fill: { r, d in
            d.id = r.id; d.title = r.title; d.notes = r.notes; d.dueDate = r.dueDate
            d.requestedAt = r.requestedAt; d.receivedAt = r.receivedAt; d.createdAt = r.createdAt
        }, link: { r, d in
            d.client = r.clientID.flatMap { clients[$0] }
            d.project = r.projectID.flatMap { projects[$0] }
        })

        _ = merge(RecurringInvoice.self, id: \.id, records: file.recurringInvoices, recordID: { $0.id }, make: { RecurringInvoice() }, fill: { r, t in
            t.id = r.id; t.name = r.name; t.nextIssueDate = r.nextIssueDate; t.termsDays = r.termsDays
            t.frequencyRaw = r.frequencyRaw; t.isActive = r.isActive; t.notes = r.notes
            t.linesData = r.linesData; t.lastGeneratedAt = r.lastGeneratedAt; t.createdAt = r.createdAt
        }, link: { r, t in t.client = r.clientID.flatMap { clients[$0] } })

        _ = merge(Expense.self, id: \.id, records: file.expenses, recordID: { $0.id }, make: { Expense() }, fill: { r, e in
            e.id = r.id; e.amount = r.amount; e.date = r.date; e.vendor = r.vendor; e.note = r.note
            e.categoryRaw = r.categoryRaw; e.deductiblePercent = r.deductiblePercent
            if let receipt = r.receiptData { e.receiptData = receipt }
            e.receiptExtension = r.receiptExtension; e.createdAt = r.createdAt
        }, link: { r, e in e.client = r.clientID.flatMap { clients[$0] } })

        _ = merge(FeeItem.self, id: \.id, records: file.feeItems ?? [], recordID: { $0.id }, make: { FeeItem() }, fill: { r, f in
            f.id = r.id; f.name = r.name; f.detail = r.detail; f.unitPrice = r.unitPrice; f.isHourly = r.isHourly
            f.sortIndex = r.sortIndex; f.createdAt = r.createdAt
        }, link: { _, _ in })

        _ = merge(BuiltInStageSetup.self, id: \.id, records: file.builtInStages ?? [], recordID: { $0.id }, make: { BuiltInStageSetup() }, fill: { r, b in
            b.id = r.id; b.serviceTypeRaw = r.serviceTypeRaw; b.stageKey = r.stageKey
            b.automationData = r.automationData; b.updatedAt = r.updatedAt
        }, link: { _, _ in })

        _ = merge(Quote.self, id: \.id, records: file.quotes ?? [], recordID: { $0.id }, make: { Quote() }, fill: { r, q in
            q.id = r.id; q.number = r.number; q.validUntil = r.validUntil; q.notes = r.notes
            q.statusRaw = r.statusRaw; q.issueDate = r.issueDate; q.linesData = r.linesData
            q.invoiceID = r.invoiceID; q.createdAt = r.createdAt
        }, link: { r, q in q.client = r.clientID.flatMap { clients[$0] } })

        _ = merge(Pipeline.self, id: \.id, records: file.pipelines ?? [], recordID: { $0.id }, make: { Pipeline() }, fill: { r, p in
            p.id = r.id; p.name = r.name; p.systemImage = r.systemImage; p.sortIndex = r.sortIndex
            p.stagesData = r.stagesData; p.createdAt = r.createdAt
        }, link: { _, _ in })

        _ = merge(LetterTemplate.self, id: \.id, records: file.letterTemplates ?? [], recordID: { $0.id }, make: { LetterTemplate() }, fill: { r, l in
            l.id = r.id; l.name = r.name; l.body = r.body; l.kindRaw = r.kindRaw; l.createdAt = r.createdAt
        }, link: { _, _ in })

        _ = merge(EmailTemplate.self, id: \.id, records: file.emailTemplates ?? [], recordID: { $0.id }, make: { EmailTemplate() }, fill: { r, e in
            e.id = r.id; e.name = r.name; e.subject = r.subject; e.body = r.body; e.createdAt = r.createdAt
        }, link: { _, _ in })

        try? context.save()
        return result
    }
}
