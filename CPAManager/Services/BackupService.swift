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

    // MARK: Records (one per model; relationships are stored as IDs)

    struct ClientRecord: Codable {
        var id: UUID; var name: String; var company: String; var entityTypeRaw: String; var statusRaw: String
        var email: String; var phone: String; var notes: String; var createdAt: Date; var qboCustomerId: String
        var tagsRaw: String; var followUpDate: Date?; var leadStageRaw: String; var leadValue: Double
        var extensionYearsRaw: String
        // Batch 5 (optional for older backups).
        var birthday: Date? = nil; var anniversary: Date? = nil
        var birthdayAckYear: Int? = nil; var anniversaryAckYear: Int? = nil
    }
    struct ProjectRecord: Codable {
        var id: UUID; var title: String; var detail: String; var statusRaw: String; var serviceTypeRaw: String
        var priorityRaw: String; var startDate: Date?; var dueDate: Date?; var completedAt: Date?; var taxYear: Int
        var templateName: String?; var createdAt: Date; var receivedDate: Date?; var nextAction: String
        var holdReasonRaw: String; var holdDetail: String; var holdResumeStatusRaw: String; var clientID: UUID?
        var pipelineID: UUID? = nil; var stageKey: String? = nil
    }
    struct TaskRecord: Codable {
        var id: UUID; var title: String; var notes: String; var isDone: Bool; var dueDate: Date?; var sortIndex: Int
        var completedAt: Date?; var createdAt: Date; var isNextAction: Bool; var snoozedUntil: Date?
        var repeatRuleRaw: String; var projectID: UUID?; var clientID: UUID?
    }
    struct TimeRecord: Codable {
        var id: UUID; var startedAt: Date; var endedAt: Date?; var notes: String; var isBillable: Bool
        var hourlyRate: Double; var projectTitle: String; var clientName: String; var createdAt: Date
        var invoiceID: UUID?; var projectID: UUID?
    }
    struct DocumentRecord: Codable {
        var id: UUID; var filename: String; var fileExtension: String; var data: Data?; var createdAt: Date
        var clientID: UUID?; var projectID: UUID?
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
        [
            ("Clients", clients.count), ("Projects", projects.count), ("Tasks", tasks.count),
            ("Time entries", timeEntries.count), ("Documents", documents.count), ("Templates", templates.count),
            ("Recurring work", engagements.count), ("Invoices", invoices.count), ("Payments", payments.count),
            ("Inbox items", inbox.count), ("Activity entries", interactions.count), ("Saved filters", savedFilters.count),
            ("Document requests", documentRequests.count), ("Recurring invoices", recurringInvoices.count),
            ("Expenses", expenses.count), ("Pipelines", pipelines?.count ?? 0),
            ("Letter templates", letterTemplates?.count ?? 0), ("Email templates", emailTemplates?.count ?? 0),
        ].filter { $0.1 > 0 }
    }

    var totalRecords: Int {
        clients.count + projects.count + tasks.count + timeEntries.count + documents.count + templates.count
            + templateTasks.count + engagements.count + invoices.count + invoiceLines.count + payments.count
            + inbox.count + interactions.count + savedFilters.count + documentRequests.count
            + recurringInvoices.count + expenses.count
            + (pipelines?.count ?? 0) + (letterTemplates?.count ?? 0) + (emailTemplates?.count ?? 0)
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
                  birthdayAckYear: c.birthdayAckYear, anniversaryAckYear: c.anniversaryAckYear)
        }
        file.projects = all(Project.self).map { p in
            BackupFile.ProjectRecord(id: p.id, title: p.title, detail: p.detail, statusRaw: p.statusRaw, serviceTypeRaw: p.serviceTypeRaw,
                  priorityRaw: p.priorityRaw, startDate: p.startDate, dueDate: p.dueDate, completedAt: p.completedAt,
                  taxYear: p.taxYear, templateName: p.templateName, createdAt: p.createdAt, receivedDate: p.receivedDate,
                  nextAction: p.nextAction, holdReasonRaw: p.holdReasonRaw, holdDetail: p.holdDetail,
                  holdResumeStatusRaw: p.holdResumeStatusRaw, clientID: p.client?.id,
                  pipelineID: p.pipelineID, stageKey: p.stageKey)
        }
        file.tasks = all(TaskItem.self).map { t in
            BackupFile.TaskRecord(id: t.id, title: t.title, notes: t.notes, isDone: t.isDone, dueDate: t.dueDate, sortIndex: t.sortIndex,
                  completedAt: t.completedAt, createdAt: t.createdAt, isNextAction: t.isNextAction,
                  snoozedUntil: t.snoozedUntil, repeatRuleRaw: t.repeatRuleRaw, projectID: t.project?.id, clientID: t.client?.id)
        }
        file.timeEntries = all(TimeEntry.self).map { t in
            BackupFile.TimeRecord(id: t.id, startedAt: t.startedAt, endedAt: t.endedAt, notes: t.notes, isBillable: t.isBillable,
                  hourlyRate: t.hourlyRate, projectTitle: t.projectTitle, clientName: t.clientName,
                  createdAt: t.createdAt, invoiceID: t.invoiceID, projectID: t.project?.id)
        }
        file.documents = all(Document.self).map { d in
            BackupFile.DocumentRecord(id: d.id, filename: d.filename, fileExtension: d.fileExtension, data: includeFiles ? d.data : nil,
                  createdAt: d.createdAt, clientID: d.client?.id, projectID: d.project?.id)
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
                  deductiblePercent: e.deductiblePercent, receiptData: includeFiles ? e.receiptData : nil,
                  receiptExtension: e.receiptExtension, createdAt: e.createdAt, clientID: e.client?.id)
        }
        file.pipelines = all(Pipeline.self).map { p in
            BackupFile.PipelineRecord(id: p.id, name: p.name, systemImage: p.systemImage, sortIndex: p.sortIndex,
                  stagesData: p.stagesData, createdAt: p.createdAt)
        }
        file.letterTemplates = all(LetterTemplate.self).map { l in
            BackupFile.LetterTemplateRecord(id: l.id, name: l.name, kindRaw: l.kindRaw, body: l.body, createdAt: l.createdAt)
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
    }

    @MainActor
    @discardableResult
    static func restore(_ file: BackupFile, into context: ModelContext) -> RestoreResult {
        var result = RestoreResult()

        func existing<T: PersistentModel>(_ type: T.Type, id: KeyPath<T, UUID>) -> [UUID: T] {
            let models = (try? context.fetch(FetchDescriptor<T>())) ?? []
            return Dictionary(models.map { ($0[keyPath: id], $0) }, uniquingKeysWith: { first, _ in first })
        }

        /// Inserts records that aren't present yet and returns the full id → model map
        /// (existing + new) so later records can link to either.
        func merge<T: PersistentModel, R>(
            _ type: T.Type, id: KeyPath<T, UUID>, records: [R], recordID: (R) -> UUID,
            make: (R) -> T, link: (R, T) -> Void
        ) -> [UUID: T] {
            var map = existing(type, id: id)
            for record in records {
                if map[recordID(record)] != nil {
                    result.skippedExisting += 1
                    continue
                }
                let model = make(record)
                context.insert(model)
                link(record, model)
                map[recordID(record)] = model
                result.inserted += 1
            }
            return map
        }

        let clients = merge(Client.self, id: \.id, records: file.clients, recordID: { $0.id }, make: { r in
            let c = Client(name: r.name, company: r.company, notes: r.notes)
            c.id = r.id; c.entityTypeRaw = r.entityTypeRaw; c.statusRaw = r.statusRaw; c.email = r.email; c.phone = r.phone
            c.createdAt = r.createdAt; c.qboCustomerId = r.qboCustomerId; c.tagsRaw = r.tagsRaw
            c.followUpDate = r.followUpDate; c.leadStageRaw = r.leadStageRaw; c.leadValue = r.leadValue
            c.extensionYearsRaw = r.extensionYearsRaw
            c.birthday = r.birthday; c.anniversary = r.anniversary
            c.birthdayAckYear = r.birthdayAckYear ?? 0; c.anniversaryAckYear = r.anniversaryAckYear ?? 0
            return c
        }, link: { _, _ in })

        let projects = merge(Project.self, id: \.id, records: file.projects, recordID: { $0.id }, make: { r in
            let p = Project(title: r.title, detail: r.detail)
            p.id = r.id; p.statusRaw = r.statusRaw; p.serviceTypeRaw = r.serviceTypeRaw; p.priorityRaw = r.priorityRaw
            p.startDate = r.startDate; p.dueDate = r.dueDate; p.completedAt = r.completedAt; p.taxYear = r.taxYear
            p.templateName = r.templateName; p.createdAt = r.createdAt; p.receivedDate = r.receivedDate
            p.nextAction = r.nextAction; p.holdReasonRaw = r.holdReasonRaw; p.holdDetail = r.holdDetail
            p.holdResumeStatusRaw = r.holdResumeStatusRaw
            p.pipelineID = r.pipelineID; p.stageKey = r.stageKey ?? ""
            return p
        }, link: { r, p in p.client = r.clientID.flatMap { clients[$0] } })

        _ = merge(TaskItem.self, id: \.id, records: file.tasks, recordID: { $0.id }, make: { r in
            let t = TaskItem(title: r.title, notes: r.notes)
            t.id = r.id; t.isDone = r.isDone; t.dueDate = r.dueDate; t.sortIndex = r.sortIndex
            t.completedAt = r.completedAt; t.createdAt = r.createdAt; t.isNextAction = r.isNextAction
            t.snoozedUntil = r.snoozedUntil; t.repeatRuleRaw = r.repeatRuleRaw
            return t
        }, link: { r, t in
            t.project = r.projectID.flatMap { projects[$0] }
            t.client = r.clientID.flatMap { clients[$0] }
        })

        let times = merge(TimeEntry.self, id: \.id, records: file.timeEntries, recordID: { $0.id }, make: { r in
            let t = TimeEntry(startedAt: r.startedAt, endedAt: r.endedAt, notes: r.notes, isBillable: r.isBillable, hourlyRate: r.hourlyRate)
            t.id = r.id; t.projectTitle = r.projectTitle; t.clientName = r.clientName
            t.createdAt = r.createdAt; t.invoiceID = r.invoiceID
            return t
        }, link: { r, t in t.project = r.projectID.flatMap { projects[$0] } })
        _ = times

        _ = merge(Document.self, id: \.id, records: file.documents, recordID: { $0.id }, make: { r in
            let d = Document(filename: r.filename, fileExtension: r.fileExtension, data: r.data ?? Data())
            d.id = r.id; d.createdAt = r.createdAt
            return d
        }, link: { r, d in
            d.client = r.clientID.flatMap { clients[$0] }
            d.project = r.projectID.flatMap { projects[$0] }
        })

        let templates = merge(WorkflowTemplate.self, id: \.id, records: file.templates, recordID: { $0.id }, make: { r in
            let t = WorkflowTemplate(name: r.name, detail: r.detail)
            t.id = r.id; t.serviceTypeRaw = r.serviceTypeRaw; t.defaultDurationDays = r.defaultDurationDays
            t.createdAt = r.createdAt
            t.pipelineID = r.pipelineID; t.startStageKey = r.startStageKey ?? ""
            return t
        }, link: { _, _ in })

        _ = merge(TemplateTask.self, id: \.id, records: file.templateTasks, recordID: { $0.id }, make: { r in
            let t = TemplateTask(title: r.title, sortIndex: r.sortIndex, dayOffset: r.dayOffset)
            t.id = r.id
            return t
        }, link: { r, t in t.template = r.templateID.flatMap { templates[$0] } })

        _ = merge(RecurringEngagement.self, id: \.id, records: file.engagements, recordID: { $0.id }, make: { r in
            let e = RecurringEngagement(name: r.name, isActive: r.isActive, nextDueDate: r.nextDueDate, leadTimeDays: r.leadTimeDays, adjustForWeekends: r.adjustForWeekends)
            e.id = r.id; e.frequencyRaw = r.frequencyRaw; e.serviceTypeRaw = r.serviceTypeRaw
            e.lastGeneratedDueDate = r.lastGeneratedDueDate; e.createdAt = r.createdAt
            e.endDate = r.endDate; e.namingPattern = r.namingPattern ?? ""
            return e
        }, link: { r, e in
            e.client = r.clientID.flatMap { clients[$0] }
            e.template = r.templateID.flatMap { templates[$0] }
        })

        let invoices = merge(Invoice.self, id: \.id, records: file.invoices, recordID: { $0.id }, make: { r in
            let i = Invoice(number: r.number, issueDate: r.issueDate, dueDate: r.dueDate, notes: r.notes)
            i.id = r.id; i.statusRaw = r.statusRaw; i.qboId = r.qboId; i.qboSyncStateRaw = r.qboSyncStateRaw
            i.qboSyncError = r.qboSyncError; i.createdAt = r.createdAt
            return i
        }, link: { r, i in i.client = r.clientID.flatMap { clients[$0] } })

        _ = merge(InvoiceLine.self, id: \.id, records: file.invoiceLines, recordID: { $0.id }, make: { r in
            let l = InvoiceLine(detail: r.detail, quantity: r.quantity, rate: r.rate, sortIndex: r.sortIndex, timeEntryID: r.timeEntryID)
            l.id = r.id
            return l
        }, link: { r, l in l.invoice = r.invoiceID.flatMap { invoices[$0] } })

        _ = merge(Payment.self, id: \.id, records: file.payments, recordID: { $0.id }, make: { r in
            let p = Payment(amount: r.amount, date: r.date, note: r.note)
            p.id = r.id; p.methodRaw = r.methodRaw; p.createdAt = r.createdAt
            return p
        }, link: { r, p in p.invoice = r.invoiceID.flatMap { invoices[$0] } })

        _ = merge(InboxItem.self, id: \.id, records: file.inbox, recordID: { $0.id }, make: { r in
            let i = InboxItem(text: r.text)
            i.id = r.id; i.sourceRaw = r.sourceRaw; i.createdAt = r.createdAt; i.isProcessed = r.isProcessed
            i.processedAt = r.processedAt; i.dedupeKey = r.dedupeKey; i.externalID = r.externalID; i.link = r.link
            return i
        }, link: { r, i in i.client = r.clientID.flatMap { clients[$0] } })

        _ = merge(Interaction.self, id: \.id, records: file.interactions, recordID: { $0.id }, make: { r in
            let i = Interaction(summary: r.summary, occurredAt: r.occurredAt)
            i.id = r.id; i.kindRaw = r.kindRaw; i.createdAt = r.createdAt
            return i
        }, link: { r, i in i.client = r.clientID.flatMap { clients[$0] } })

        _ = merge(SavedClientFilter.self, id: \.id, records: file.savedFilters, recordID: { $0.id }, make: { r in
            let f = SavedClientFilter(name: r.name)
            f.id = r.id; f.statusRaw = r.statusRaw; f.entityTypeRaw = r.entityTypeRaw; f.tag = r.tag
            f.onlyWithOpenWork = r.onlyWithOpenWork; f.createdAt = r.createdAt
            return f
        }, link: { _, _ in })

        _ = merge(DocumentRequest.self, id: \.id, records: file.documentRequests, recordID: { $0.id }, make: { r in
            let d = DocumentRequest(title: r.title, notes: r.notes, dueDate: r.dueDate)
            d.id = r.id; d.requestedAt = r.requestedAt; d.receivedAt = r.receivedAt; d.createdAt = r.createdAt
            return d
        }, link: { r, d in
            d.client = r.clientID.flatMap { clients[$0] }
            d.project = r.projectID.flatMap { projects[$0] }
        })

        _ = merge(RecurringInvoice.self, id: \.id, records: file.recurringInvoices, recordID: { $0.id }, make: { r in
            let t = RecurringInvoice(name: r.name, nextIssueDate: r.nextIssueDate, termsDays: r.termsDays)
            t.id = r.id; t.frequencyRaw = r.frequencyRaw; t.isActive = r.isActive; t.notes = r.notes
            t.linesData = r.linesData; t.lastGeneratedAt = r.lastGeneratedAt; t.createdAt = r.createdAt
            return t
        }, link: { r, t in t.client = r.clientID.flatMap { clients[$0] } })

        _ = merge(Expense.self, id: \.id, records: file.expenses, recordID: { $0.id }, make: { r in
            let e = Expense(amount: r.amount, date: r.date, vendor: r.vendor, note: r.note)
            e.id = r.id; e.categoryRaw = r.categoryRaw; e.deductiblePercent = r.deductiblePercent
            e.receiptData = r.receiptData ?? Data(); e.receiptExtension = r.receiptExtension; e.createdAt = r.createdAt
            return e
        }, link: { r, e in e.client = r.clientID.flatMap { clients[$0] } })

        _ = merge(Pipeline.self, id: \.id, records: file.pipelines ?? [], recordID: { $0.id }, make: { r in
            let p = Pipeline(name: r.name, systemImage: r.systemImage, sortIndex: r.sortIndex)
            p.id = r.id; p.stagesData = r.stagesData; p.createdAt = r.createdAt
            return p
        }, link: { _, _ in })

        _ = merge(LetterTemplate.self, id: \.id, records: file.letterTemplates ?? [], recordID: { $0.id }, make: { r in
            let l = LetterTemplate(name: r.name, body: r.body)
            l.id = r.id; l.kindRaw = r.kindRaw; l.createdAt = r.createdAt
            return l
        }, link: { _, _ in })

        _ = merge(EmailTemplate.self, id: \.id, records: file.emailTemplates ?? [], recordID: { $0.id }, make: { r in
            let e = EmailTemplate(name: r.name, subject: r.subject, body: r.body)
            e.id = r.id; e.createdAt = r.createdAt
            return e
        }, link: { _, _ in })

        try? context.save()
        return result
    }
}
