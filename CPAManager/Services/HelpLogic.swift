import Foundation

// In-app help, tips and first-run rules. Pure so it can be unit-tested.

struct HelpTopic: Equatable, Identifiable {
    var id: String
    var title: String
    var systemImage: String
    var summary: String
    var body: String
    /// Extra words people might search for.
    var keywords: String = ""
}

enum HelpCatalog {
    static let topics: [HelpTopic] = [
        HelpTopic(
            id: "today", title: "Your daily loop: Today", systemImage: "sun.max.fill",
            summary: "One screen for what's overdue, due today and what to do next.",
            body: """
            Today pulls together tasks, project deadlines, client follow-ups, unpaid invoices and document requests.

            • Type in the bar at the top to add a task. Phrases like "tomorrow", "friday" or "every month" set the date and repeat.
            • Swipe a task right to finish it, left to push it to tomorrow. Press and hold for snooze, reschedule, repeat and Start timer.
            • "Next up" holds undated tasks you marked as do-next; snoozed tasks come back on their day.
            """,
            keywords: "tasks overdue quick add swipe snooze repeat"
        ),
        HelpTopic(
            id: "capture", title: "Capturing texts and email", systemImage: "tray.and.arrow.down.fill",
            summary: "Get things out of your head and into the Inbox.",
            body: """
            Anything you capture lands in the Inbox until you decide what it is: a task, a client note, or nothing.

            • Texts: have Siri digest them into an Apple Note, then run the Shortcuts automation from Today ▸ Capture options ▸ Set up. It adds each line to the Inbox and never adds the same line twice.
            • Email: connect Gmail in Settings, or use the Share Sheet on any email.
            • Siri and the Action button: "Capture a thought" adds to the Inbox hands-free.
            """,
            keywords: "inbox siri shortcuts gmail share sheet messages"
        ),
        HelpTopic(
            id: "clients", title: "Clients, tags and follow-ups", systemImage: "person.2.fill",
            summary: "Keep a history for every client and never lose track of who to call.",
            body: """
            Open a client to log calls, emails, texts and meetings. "Last contact" updates itself.

            • Set a follow-up date and the client appears on Today from that day. Logging a contact clears it.
            • Tags (e.g. referral, bookkeeping) filter the client list; save a filter you use often.
            • Birthdays and "client since" dates show on Today the day they come up.
            • Notes support # headings, - bullets and - [ ] checkboxes you can tick on the client screen.
            """,
            keywords: "crm interactions birthday anniversary notes markdown checkbox"
        ),
        HelpTopic(
            id: "leads", title: "Leads pipeline", systemImage: "funnel.fill",
            summary: "Track prospects from first contact to won or lost.",
            body: """
            Prospects move through New, Contacted, Proposal sent, then Won or Lost. Won makes them an active client; Lost marks them inactive — nothing is ever deleted.
            """,
            keywords: "prospect proposal won lost"
        ),
        HelpTopic(
            id: "pipelines", title: "Pipelines and stages", systemImage: "rectangle.split.3x1.fill",
            summary: "Build your own workflows, like Bookkeeping or Client Onboarding.",
            body: """
            The built-in "Tax Return" pipeline is always there. Under More ▸ Pipelines you can create others with your own stages.

            • Each stage says what it "behaves like" (Working, Waiting, Review, Done) so reports and reminders keep working.
            • A stage can add tasks and reset the due date when a job enters it.
            • On the Work tab switch to the board to drag jobs between stages, and use the pipeline filter in the list.
            • Point a template at a pipeline and stage, and every job made from it (including recurring work) starts there.
            """,
            keywords: "workflow board kanban stage taxdome automation"
        ),
        HelpTopic(
            id: "recurring", title: "Recurring work", systemImage: "arrow.triangle.2.circlepath",
            summary: "Monthly closes, quarterly estimates and more, created for you.",
            body: """
            More ▸ Recurring Work generates a job before each due date. Use "Set up for several clients" to add the same schedule to many clients at once.

            • Naming pattern: use {client}, {month}, {year}, {quarter} and more; the Upcoming list previews the titles.
            • Set an end date to stop automatically. Swipe a row to skip the next one or pause it.
            """,
            keywords: "monthly quarterly bookkeeping schedule naming pattern skip pause"
        ),
        HelpTopic(
            id: "letters", title: "Letters, proposals and email templates", systemImage: "doc.richtext",
            summary: "Fill in engagement letters and emails for a client in seconds.",
            body: """
            More ▸ Letters & Emails holds your templates. Merge fields like {client}, {firstname}, {fee} and {taxyear} are filled in from the client.

            • On a client, "Draft letter or proposal" makes a PDF with a signature block and saves it to their documents.
            • "Email from template" opens your mail app with the message ready, and logs it on the client.
            """,
            keywords: "engagement letter proposal pdf mail template merge"
        ),
        HelpTopic(
            id: "time", title: "Time tracking and billing", systemImage: "clock.fill",
            summary: "Start a timer anywhere and bill it without retyping.",
            body: """
            Start a timer from a project, the Time tab, or a task's menu on Today. Unbilled time goes onto an invoice from Invoices.

            • Settings ▸ Billing can round billed time up to 6, 15, 30 or 60 minutes.
            • Settings ▸ Billing can also warn you if a timer runs longer than a set number of hours.
            """,
            keywords: "timer hours invoice rounding billable"
        ),
        HelpTopic(
            id: "invoices", title: "Invoices and payments", systemImage: "doc.text.fill",
            summary: "Draft, send, record payments and see what's overdue.",
            body: """
            Invoices can be built from time entries. Record full or partial payments; only sent invoices with a balance count as overdue and show on Today. Recurring invoices are drafted for you, never sent automatically.
            """,
            keywords: "payment overdue quickbooks recurring invoice"
        ),
        HelpTopic(
            id: "quotes", title: "Quotes and fee schedule", systemImage: "doc.plaintext",
            summary: "Price a job before you start and turn it into an invoice.",
            body: """
            More ▸ Fee Schedule holds your standard prices. More ▸ Quotes lets you pick a client, add lines (or pick from the fee schedule), set a valid-until date and export a PDF with a signature block.

            • "Create draft invoice" on a quote makes an invoice with the same lines and marks the quote accepted. It only works once per quote.
            • A client can have their own hourly rate, and can be marked flat-fee (their timers start as non-billable). Set both when editing the client.
            """,
            keywords: "estimate proposal price rate flat fee hourly"
        ),
        HelpTopic(
            id: "uploads", title: "Client uploads and signatures", systemImage: "signature",
            summary: "Use your secure upload page and track letters sent for signature.",
            body: """
            Paste your secure upload page (for example an Encyro page) in Settings ▸ Client uploads & signatures. It's added to document-request emails and available as the {uploadlink} field in letter and email templates.

            When you save a letter or proposal as a PDF, "Track it as sent for signature" marks it as awaiting signature. Send it through your signing tool, then long-press the document on the client and choose "Mark signed" when it comes back. Unsigned letters show on Today after the number of days you set.
            """,
            keywords: "encyro esign e-signature portal upload link secure"
        ),
        HelpTopic(
            id: "subtasks", title: "Subtasks and waiting", systemImage: "checklist",
            summary: "Break a task down and hold it until something else is done.",
            body: """
            Tap the (i) on a task (or "Details…" in its long-press menu on Today) to add subtasks, note what you're waiting on, and choose another task it can't start until. A blocked task stays off Today and comes back automatically when the other task is finished.
            """,
            keywords: "checklist dependency blocked waiting on client"
        ),
        HelpTopic(
            id: "import", title: "Importing from a spreadsheet or QuickBooks", systemImage: "square.and.arrow.down",
            summary: "Bring in clients or time entries from a CSV file.",
            body: """
            More ▸ Import from CSV reads a spreadsheet saved as CSV. Columns are matched by name (Name or Customer, Company, Email, Phone, Entity type, Tags, Notes; or Date, Hours, Client, Project, Rate). A QuickBooks customer list exported to CSV works. You see a preview and the reasons any rows would be skipped before anything is imported. Clients whose email or name already exist are skipped.
            """,
            keywords: "csv excel spreadsheet quickbooks customers bulk time"
        ),
        HelpTopic(
            id: "health", title: "Data health and tax season", systemImage: "stethoscope",
            summary: "Fix sync leftovers and see your season at a glance.",
            body: """
            More ▸ Data Health looks for invoice numbers used twice (two devices creating invoices before syncing), duplicate default templates, clients sharing an email, and timers left running for a very long time, and fixes the safe ones.

            During tax season (January to April 20 and October 1–20 by default) Today shows a card with days to the deadline, open returns by stage, clients with no return started, extensions and documents still owed. Change or turn it off in Settings.
            """,
            keywords: "duplicate invoice number sync repair tax season extensions deadline"
        ),
        HelpTopic(
            id: "deadlines", title: "Tax deadlines and document requests", systemImage: "calendar",
            summary: "Create the year's tax dates and chase what clients owe you.",
            body: """
            On a client, generate tax deadlines for their entity type — weekend and holiday shifts are handled. Document requests list what a client owes you; ones with a due date show on Today, and you can copy a chase email.
            """,
            keywords: "extension 1040 1120 documents checklist"
        ),
        HelpTopic(
            id: "search", title: "Search and shortcuts", systemImage: "magnifyingglass",
            summary: "Find anything, and jump around without the mouse.",
            body: """
            Press ⌘K (or tap the magnifier) to search clients, work, tasks, invoices, expenses and notes, or to run a command.

            On Mac: ⌘N new task, ⇧⌘N quick capture, ⌘1–6 switch sections. A menu bar item and ⌃⌥Space capture from anywhere.
            """,
            keywords: "command palette spotlight keyboard mac menu bar"
        ),
        HelpTopic(
            id: "sync", title: "Sync and backup", systemImage: "icloud.fill",
            summary: "Your data lives in your own iCloud.",
            body: """
            Data syncs between your iPhone, iPad and Mac through your iCloud account — there's no separate server. Settings and saved logins sync too.

            Settings ▸ Backup exports one file with everything; restoring merges it in and never deletes anything. Export CSVs for spreadsheets.
            """,
            keywords: "icloud cloudkit export restore csv"
        ),
        HelpTopic(
            id: "widgets", title: "Widgets, Siri and Apple Watch", systemImage: "applewatch",
            summary: "Get at your day without opening the app.",
            body: """
            Add the Today widget to your Home or Lock Screen. Tick a task in the widget and it's completed the next time the app opens. The Apple Watch app shows today's tasks and lets you complete them and start a timer.
            """,
            keywords: "lock screen complication watch control center"
        ),
    ]

    static func topic(id: String) -> HelpTopic? { topics.first { $0.id == id } }

    /// Help topics as search docs so the shared ranking (`GlobalSearch`) applies.
    static func search(_ query: String, topics: [HelpTopic] = HelpCatalog.topics) -> [HelpTopic] {
        let docs = topics.map {
            SearchDoc(id: $0.id, kind: .note, title: $0.title, subtitle: $0.summary, keywords: $0.keywords + " " + $0.body)
        }
        let byID = Dictionary(uniqueKeysWithValues: topics.map { ($0.id, $0) })
        return GlobalSearch.search(docs, query: query, limit: topics.count).compactMap { byID[$0.id] }
    }
}

enum Tips {
    static let all: [String] = [
        "Type “call Dana tomorrow” in the Today bar — the date is picked out for you.",
        "Swipe a task left to push it to tomorrow without opening it.",
        "Press and hold a task on Today to start a timer on its project.",
        "Set a follow-up date on a client and they'll show up on Today that day.",
        "Use a pipeline stage's entry tasks to stop retyping the same checklist.",
        "Recurring work can be set up for many clients at once from the + menu.",
        "Tick checkboxes in a client's notes — start a line with “- [ ] ”.",
        "⌘K searches everything, and also runs commands like “new client”.",
        "Share an email to the app to drop it in your Inbox.",
        "Weekly Review shows which clients have gone quiet.",
        "Round billed time up to 15 minutes in Settings ▸ Billing.",
        "Add birthdays to a client so Today reminds you to send a note.",
        "Turn an accepted quote into a draft invoice with one tap.",
        "Paste your secure upload link in Settings and it goes into every document-request email.",
        "Long-press a letter in a client's documents to mark it signed.",
    ]

    /// One tip per calendar day, rotating through the list.
    static func tip(forDay day: Date, calendar: Calendar = .current) -> String {
        let ordinal = calendar.ordinality(of: .day, in: .era, for: day) ?? 0
        return all[abs(ordinal) % all.count]
    }
}

enum OnboardingPolicy {
    /// Show the first-run walkthrough only to genuinely new users: not if they've already
    /// finished it, and not for existing installs that predate it (which already have a
    /// firm name, invoices, time entries or a completed review).
    static func shouldShow(hasOnboarded: Bool, firmName: String, invoiceCount: Int, timeEntryCount: Int, lastReviewTime: Double) -> Bool {
        if hasOnboarded { return false }
        if !firmName.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        if invoiceCount > 0 || timeEntryCount > 0 { return false }
        if lastReviewTime > 0 { return false }
        return true
    }
}
