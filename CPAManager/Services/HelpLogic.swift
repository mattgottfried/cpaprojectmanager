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
            Every service (Tax Return, Bookkeeping, Payroll, Advisory, IRS Notice, Other) has its own pipeline. Tax returns use Not Started, In Progress, On Hold, Awaiting Signature, Ready to File, Filed and Complete. The others use Not Started, In Progress, Waiting on Client and Completed.

            On Hold and Waiting on Client are never entered automatically: "Advance" skips them and you pick them yourself. Under More ▸ Pipelines you can create your own pipeline with custom stages and choose it for a service, so new work of that service starts there.

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
            Tap the (i) on a task (or "Details…" in its long-press menu on Today) to add subtasks, note what you're waiting on, and choose another task it can't start until. A blocked task stays off Today and comes back automatically when the other task is finished. Tasks a pipeline stage creates work this way: only the first has a due date, and each next one is dated when the one before it is completed. Steps from a template work the same way.
            """,
            keywords: "checklist dependency blocked waiting on client"
        ),
        HelpTopic(
            id: "import", title: "Importing from a spreadsheet", systemImage: "square.and.arrow.down",
            summary: "Bring in clients or time entries from a CSV file.",
            body: """
            More ▸ Import from CSV reads a spreadsheet saved as CSV. Columns are matched by name (Name or Customer, Company, Email, Phone, Entity type, Tags, Notes; or Date, Hours, Client, Project, Rate). A QuickBooks customer list exported to CSV works. You see a preview and the reasons any rows would be skipped before anything is imported. Clients whose email or name already exist are skipped.

            Choose "Fee schedule" to import your prices: Name and Price columns (optionally Description and Hourly). They land in More ▸ Fee Schedule, ready for quotes and invoices.
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
            summary: "Keep your iPhone, iPad and Mac in step.",
            body: """
            Data syncs through Cloud Firestore in your own Firebase project. Set it up once (docs/FIRESTORE_SETUP.md), then Settings ▸ Cloud Sync ▸ Create account, and sign in with the same account on every device. Edits sync within a couple of seconds; Settings ▸ Cloud Sync shows the status and last sync time.

            If a device suddenly looks like it lost many records, sync pauses and asks whether to restore them from the cloud or delete them everywhere. Files over about 0.8 MB stay on the device that added them.

            Settings ▸ Backup exports one file with everything, independent of any cloud; restoring merges it in and never deletes anything. Export CSVs for spreadsheets.
            """,
            keywords: "firebase firestore cloud sync account sign in export restore csv backup icloud"
        ),
        HelpTopic(
            id: "widgets", title: "Widgets, Siri and Apple Watch", systemImage: "applewatch",
            summary: "Get at your day without opening the app.",
            body: """
            Add the Today widget to your Home or Lock Screen. Tick a task in the widget and it's completed the next time the app opens. The Apple Watch app shows today's tasks and lets you complete them and start a timer.
            """,
            keywords: "lock screen complication watch control center"
        ),
        HelpTopic(
            id: "taskspage", title: "Tasks page and Insights", systemImage: "tablecells",
            summary: "Every task in one table, and a dashboard for the practice.",
            body: """
            Today has a switcher at the top: Focus (your daily plan), Tasks and Insights.

            Tasks lists every task with its job, client, status, due date and priority. Use the Pending / Completed tabs, Presets (saved views), Filter, Group and Sort; tap a column heading to sort. Tap a status or priority pill to change it, tick the circle to complete, or Select to update or delete several at once. Board shows pending tasks in columns by status (drag to change); Calendar shows what's due each day. Export writes the rows you see to a CSV.

            Insights shows tasks to do for a day by priority, job counters (approaching deadline, no activity, overdue, in progress), jobs by stage, planned vs done per week, and money and time. Edit widgets turns them on or off and reorders them.
            """,
            keywords: "tasks table insights dashboard workflow board calendar filter presets overdue"
        ),
        HelpTopic(
            id: "drivefolders", title: "Drive folders and file names", systemImage: "folder.badge.gearshape",
            summary: "Numbered client folders, filing by document type, and naming.",
            body: """
            Settings ▸ Google ▸ Folders, routing and file names. Choose the Drive folder that holds your clients, and a client's folder (with 00 Permanent, 01 Intake, 02 Source Documents, 03 Deliverables with a year folder, 04 Invoices & Engagements by default) is created when you add a client or start a tax return, or from the client's Drive section. Folders are recognised by their number, so existing ones are reused, never duplicated.

            Scans and client files go to 02, letters, invoices and quotes to 04, finished returns to 03 ▸ the tax year. A job with its own Drive folder files there instead. File names come from a pattern such as "{year} - {client} - {title}". When a file shows up in a client's upload folder that matches something under "Documents needed", the app offers to mark it received.
            """,
            keywords: "google drive folders structure year naming pattern routing client folder auto create received documents needed"
        ),
        HelpTopic(
            id: "tasktools", title: "Task comments, time and bulk templates", systemImage: "text.bubble",
            summary: "Notes thread, timers and adding a checklist to many jobs.",
            body: """
            Open a task's details for a dated comment thread and a Start timer button; the time is logged on the task's job and the task shows its total. On the Tasks page, "Add template tasks…" (or the same action in Select mode, and on the Work list) adds a template's tasks to many jobs at once, skipping tasks a job already has open and chaining each job's new tasks so only the first is dated.

            The This Week widget lists tasks due in the next seven days; ask Siri "What's due this week in CPA Manager".
            """,
            keywords: "comments notes thread timer time bulk template tasks widget siri week"
        ),
        HelpTopic(
            id: "automove", title: "Automove to the next stage", systemImage: "arrow.right.circle",
            summary: "Move a job on when a stage's tasks are all done.",
            body: """
            In a stage's task setup (More ▸ Pipelines ▸ Set up stage tasks, or a custom pipeline's stage), switch on "Automove". When every task that stage created is completed, the job moves to the next stage and that stage's tasks are created. Waiting / On Hold stages are never entered automatically. Tasks that didn't come from a stage (or an older stage) never trigger it.

            Two more options live in the same place. "Time limit for this stage" counts the days a job sits in the stage; past the limit it shows on the job and under Insights ▸ Over stage time limit. "Move on only when…" adds conditions to automove: every task done, requested documents received, the job's invoice paid, no document waiting for a signature. When a condition becomes true later (a payment arrives) the job moves the next time the app opens.

            "Remind me if a job sits here" makes you a follow-up task (due today) when a job stays in the stage that many days — once per stay. Stages where you're waiting on the client (Waiting on Client, Awaiting Signature, or a custom "waiting" stage) remind after 7 days by default; switch it off or change the days in the stage setup.
            """,
            keywords: "automove automatic advance next stage complete tasks taxdome time limit conditions overdue stage clock"
        ),
        HelpTopic(
            id: "stagetasks", title: "Tasks for each stage", systemImage: "list.bullet.rectangle",
            summary: "Give every stage of a service its own tasks.",
            body: """
            More ▸ Pipelines lists each service with its built-in stages. Tap "Set up stage tasks…" under a service and add the tasks each stage should create — "Awaiting Signature" can have its own, "Ready to File" its own, and so on. Your built-in statuses stay exactly as they are.

            • The tasks appear when a job enters the stage: Advance, the status picker, dragging on the board, or completing the job. New jobs get the first stage's tasks.
            • Only the first task gets a due date; each next one is dated when the one before it is completed ("due in N days" counts from that day).
            • A stage can also reset the job's due date.
            """,
            keywords: "stage tasks automatic built-in status checklist each step"
        ),
        HelpTopic(
            id: "drive", title: "Google Drive", systemImage: "externaldrive.fill",
            summary: "Documents live in Drive; the app is a window into it.",
            body: """
            Connect Google in Settings ▸ Google (tap Reconnect once if you connected before saving to Drive was added). Then on a client or job choose "Choose Drive folder…": the newest files in that folder show right on the screen and open in Drive.

            In Documents, "Link from Google Drive…" attaches individual files. They stay in Drive; signature tracking still works on them.

            Scans, photos, files, letters, quotes and invoice PDFs you add are filed into the job's (else the client's) Drive folder, and the app keeps just a link. If there's no folder yet, the file stays in the app with a note; choose a folder, then use "Move to Google Drive" on it (or "Move in-app files to Drive" in Add Document). The app only ever creates files in Drive — it never edits, moves or deletes yours. Settings ▸ Google turns filing off.
            """,
            keywords: "google drive folder documents link files storage save upload scan move"
        ),
        HelpTopic(
            id: "selecting", title: "Select several, undo, and keyboard", systemImage: "checkmark.circle",
            summary: "Bulk actions on jobs and clients, and quick undo.",
            body: """
            In Work and Clients, tap Select (or the + menu ▸ Select Jobs) to tick several rows, then use the bar at the bottom: advance, complete or set a due date for jobs; add a tag or change the status for clients; or delete.

            Deletes and bulk changes show an Undo at the bottom for a few seconds. On a Mac: ↑/↓ move a highlight, Return opens, Space ticks, Delete removes; right-click any row for Delete.
            """,
            keywords: "bulk multiple select undo delete keyboard shortcuts mac"
        ),
        HelpTopic(
            id: "extensions", title: "Extensions", systemImage: "calendar.badge.clock",
            summary: "Decide, file and track extensions for a tax year.",
            body: """
            Extensions (More, or the sidebar's Tools) lists your clients for a tax year: those who still need a decision, those extended, and those finished. "Mark extended" moves the client's open return to the extended due date and logs it; you can undo it. An extension gives more time to file, not to pay.
            """,
            keywords: "extension 4868 7004 extended due date october september"
        ),
        HelpTopic(
            id: "billjob", title: "Billing a finished job", systemImage: "doc.badge.plus",
            summary: "Turn a finished job into an invoice and catch what was missed.",
            body: """
            On a job, "Create invoice…" bills its unbilled time plus any fee-schedule items. Reports ▸ "Finished, not billed" lists finished jobs that never went on an invoice — bill them, or mark them Not billable or Billed elsewhere. Reports also shows what each client really pays per hour.

            Overdue invoices have "Email a payment reminder" (firmer the later it is); it's logged on the client.
            """,
            keywords: "invoice unbilled profitability hourly rate reminder overdue"
        ),
        HelpTopic(
            id: "backups", title: "Backups and sync health", systemImage: "externaldrive.fill.badge.timemachine",
            summary: "Automatic daily backups and a plain-English sync check.",
            body: """
            Settings ▸ Automatic Backups keeps a full backup on this device every day (the last 7). Restoring adds back anything missing and never deletes. Settings ▸ Sync Health explains how cloud sync is doing, compares record counts between devices, and merges duplicate clients (with undo).
            """,
            keywords: "backup restore sync health duplicates merge safety"
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
        "Give each stage of a service its own tasks under More ▸ Pipelines ▸ Set up stage tasks.",
        "Pick a client's Google Drive folder and its newest files show on their screen.",
        "Deleted the wrong thing? Undo appears at the bottom for a few seconds.",
        "Give a stage a time limit and jobs that linger show up in Insights.",
        "Add the This Week widget, or ask Siri what's due this week.",
        "Extensions lists who still needs a decision for the tax year.",
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
