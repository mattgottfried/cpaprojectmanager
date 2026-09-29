import Foundation
import SwiftData

/// Store-facing Google sync. All parsing/diffing lives in `GoogleParsing.swift`.
enum GoogleSync {
    private static var lastGmail = Date.distantPast
    private static var lastCalendar = Date.distantPast

    static var defaults: UserDefaults { .standard }

    static var gmailEnabled: Bool { defaults.bool(forKey: SettingsKeys.googleGmailEnabled) }
    static var pushEnabled: Bool { defaults.bool(forKey: SettingsKeys.googlePushEnabled) }
    static var scheduleEnabled: Bool { defaults.bool(forKey: SettingsKeys.googleScheduleEnabled) }
    static var calendarID: String {
        let id = defaults.string(forKey: SettingsKeys.googleCalendarID) ?? ""
        return id.isEmpty ? "primary" : id
    }

    // MARK: Gmail → Inbox

    struct GmailResult: Equatable {
        var added = 0
        var error: String?
    }

    /// Pulls emails matching the user's Gmail search (default: starred, last 30 days)
    /// into the Inbox. Idempotent: each message is imported once, keyed by Gmail ID.
    @MainActor
    @discardableResult
    static func syncGmail(auth: GoogleAuthService, context: ModelContext, force: Bool = false) async -> GmailResult {
        guard auth.isConnected else { return GmailResult(added: 0, error: GoogleError.notConnected.errorDescription) }
        if !force && Date.now.timeIntervalSince(lastGmail) < 600 { return GmailResult() }
        lastGmail = .now

        let api = GoogleAPI(auth: auth)
        let query = GmailParsing.effectiveQuery(defaults.string(forKey: SettingsKeys.googleGmailQuery) ?? "")
        do {
            let refs = try await api.gmailMessageIDs(query: query)
            let existing = (try? context.fetch(FetchDescriptor<InboxItem>())) ?? []
            var known = Set(existing.map(\.externalID).filter { !$0.isEmpty })
            let clients = (try? context.fetch(FetchDescriptor<Client>())) ?? []
            let clientEmails = clients.map(\.email)

            var added = 0
            for ref in refs {
                let externalID = GmailParsing.externalID(ref.id)
                guard known.insert(externalID).inserted else { continue }

                let email = GmailParsing.parse(try await api.gmailMessage(id: ref.id))
                let item = InboxItem(text: GmailParsing.inboxText(email), source: .email)
                item.externalID = externalID
                item.link = GmailParsing.webLink(threadID: email.threadID)
                if let date = email.date { item.createdAt = date }
                if let index = GmailParsing.matchClientIndex(senderEmail: email.senderEmail, clientEmails: clientEmails) {
                    item.client = clients[index]
                }
                context.insert(item)
                added += 1
            }
            if added > 0 { try? context.save() }
            defaults.set(Date.now.timeIntervalSince1970, forKey: SettingsKeys.googleLastGmailSync)
            return GmailResult(added: added, error: nil)
        } catch {
            return GmailResult(added: 0, error: error.localizedDescription)
        }
    }

    // MARK: Calendar → Today

    /// Today's events from the user's calendar (excludes events this app pushed).
    static func todaysSchedule(auth: GoogleAuthService) async -> [CalendarEvent] {
        guard auth.isConnected else { return [] }
        let start = Calendar.current.startOfDay(for: .now)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return [] }
        do {
            let events = try await GoogleAPI(auth: auth).events(from: start, to: end, calendarID: "primary")
            return CalendarParsing.events(events, on: start)
        } catch {
            return []
        }
    }

    // MARK: Due dates → Calendar

    /// Everything dated and still open, as all-day calendar items (next 90 days).
    @MainActor
    static func syncItems(context: ModelContext, now: Date = .now) -> [CalendarSyncItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let horizon = calendar.date(byAdding: .day, value: 90, to: today) else { return [] }
        func inWindow(_ date: Date) -> Bool { calendar.startOfDay(for: date) >= today && date < horizon }

        var items: [CalendarSyncItem] = []
        for task in (try? context.fetch(FetchDescriptor<TaskItem>())) ?? [] where !task.isDone {
            guard let due = task.dueDate, inWindow(due), task.project?.status.isComplete != true else { continue }
            let notes = task.project.map { "Project: \($0.title)" } ?? (task.client.map { "Client: \($0.displayName)" } ?? "")
            items.append(CalendarSyncItem(id: task.id, title: task.title, day: due, notes: notes))
        }
        for project in (try? context.fetch(FetchDescriptor<Project>())) ?? [] where !project.status.isComplete {
            guard let due = project.dueDate, inWindow(due) else { continue }
            items.append(CalendarSyncItem(id: project.id, title: "Due: \(project.title)", day: due, notes: project.clientName))
        }
        for invoice in (try? context.fetch(FetchDescriptor<Invoice>())) ?? [] where invoice.status == .sent && invoice.balance > 0 {
            guard inWindow(invoice.dueDate) else { continue }
            items.append(CalendarSyncItem(
                id: invoice.id,
                title: "Invoice due: \(invoice.displayNumber) (\(Format.currency(invoice.balance)))",
                day: invoice.dueDate,
                notes: invoice.client?.displayName ?? ""
            ))
        }
        for client in (try? context.fetch(FetchDescriptor<Client>())) ?? [] where client.status != .inactive {
            guard let due = client.followUpDate, inWindow(due) else { continue }
            items.append(CalendarSyncItem(id: client.id, title: "Follow up: \(client.displayName)", day: due, notes: ""))
        }
        return items
    }

    static func loadSynced() -> [String: String] {
        guard let data = defaults.data(forKey: SettingsKeys.googleSyncedEvents),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }

    static func saveSynced(_ map: [String: String]) {
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: SettingsKeys.googleSyncedEvents)
        }
    }

    struct PushResult: Equatable {
        var created = 0
        var updated = 0
        var deleted = 0
        var error: String?
    }

    /// Makes the chosen Google calendar match the app's dated items. Only touches
    /// events this app created (deterministic `cpa…` IDs).
    @MainActor
    @discardableResult
    static func pushDueDates(auth: GoogleAuthService, context: ModelContext, force: Bool = false) async -> PushResult {
        guard auth.isConnected else { return PushResult(error: GoogleError.notConnected.errorDescription) }
        if !force && Date.now.timeIntervalSince(lastCalendar) < 300 { return PushResult() }
        lastCalendar = .now

        let api = GoogleAPI(auth: auth)
        let calendarID = self.calendarID
        var synced = loadSynced()
        let plan = CalendarSyncPlanner.plan(items: syncItems(context: context), synced: synced)
        var result = PushResult()

        do {
            for item in plan.creates {
                try await api.upsertEvent(item, calendarID: calendarID)
                synced[item.eventID] = item.signature()
                result.created += 1
            }
            for item in plan.updates {
                try await api.upsertEvent(item, calendarID: calendarID)
                synced[item.eventID] = item.signature()
                result.updated += 1
            }
            for id in plan.deletes {
                try await api.deleteEvent(id: id, calendarID: calendarID)
                synced.removeValue(forKey: id)
                result.deleted += 1
            }
        } catch {
            result.error = error.localizedDescription
        }
        saveSynced(synced)   // keep partial progress so a retry doesn't redo it
        return result
    }

    /// Removes everything we pushed (used when the user turns push off or disconnects).
    @MainActor
    static func removeAllPushedEvents(auth: GoogleAuthService) async {
        guard auth.isConnected else { return }
        let api = GoogleAPI(auth: auth)
        var synced = loadSynced()
        for id in synced.keys.sorted() {
            if (try? await api.deleteEvent(id: id, calendarID: calendarID)) != nil {
                synced.removeValue(forKey: id)
            }
        }
        saveSynced(synced)
    }
}
