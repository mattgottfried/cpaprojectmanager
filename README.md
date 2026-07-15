# CPA Project Manager

A native **iOS + iPadOS** practice-management app for a solo CPA firm — in the
spirit of TaxDome / Karbon / Canopy, but lean and pleasant to use on iPhone and
iPad. Built with **SwiftUI + SwiftData**, it syncs across your devices **for free
through your own iCloud** (CloudKit) — no server, no login, no monthly cost.

It includes the Apple-native touches that make an iPhone app feel great:
- a **billable-hours timer** that runs as a **Live Activity** on the lock screen
  and in the Dynamic Island, and
- a **"Due Today" home-screen widget**,
- plus **local notifications** for upcoming due dates.

---

## Features

| Area | What it does |
|------|--------------|
| **Dashboard** | Overdue / due-today / open-work counts, an active-timer banner, quick "New Tax Return" intake, "coming up" and "in progress" lists. |
| **Clients** | Searchable CRM with entity type (1040, 1120-S, 1065, 1120, 1041, 990), status, notes, tap-to-call/text/email, and one-tap **import from your iPhone Contacts**. |
| **Work** | Projects broken into checkable tasks, with a **9-stage pipeline** (Not Started → Awaiting Docs → In Progress → On Hold → In Review → Awaiting Signature → Ready to File → Filed → Complete) matching a real CPA workflow. One-tap **Advance** steps a project forward and pushes its due date out; **Put on Hold** records a reason and remembers which stage to resume at. Switch between a list and a drag-and-drop **kanban board** (great on iPad). |
| **Deadlines** | Everything due, grouped **Overdue / Today / This Week / Later**, a reference list of standard US filing dates, and **Add to Calendar** on any item. |
| **Documents** | Scan paper documents with the camera (combined into one PDF), or attach a photo or file, on any client or project. Tap to preview; synced like everything else. |
| **Templates** | Reusable engagement checklists. Instantiating one creates a project with tasks whose due dates are computed from each step's day-offset. |
| **Recurring work** | Monthly bookkeeping, quarterly estimates, payroll (weekly/biweekly/monthly/quarterly/annually), etc. — auto-generates a project from a template when its lead-time window opens, then advances the schedule. |
| **Time & billing** | Start/stop timer (also a Live Activity), a running billable total for the month, and a time log with an unbilled-time indicator. |
| **Invoicing** | Build an invoice from a client's unbilled time (one line per entry), generate a clean PDF, and share it by email/Messages/AirDrop. Optionally **push it straight into QuickBooks Online** — see the QuickBooks section below. |
| **Reports** | Billable hours & amount by client for month/quarter/YTD, unbilled work in progress, open work by pipeline stage, and what's overdue. |

The app **seeds itself on first launch** with a few sample clients and five default
templates (1040, 1120-S, Monthly Bookkeeping, Quarterly Estimates, Payroll Run) so
it isn't empty. You can edit or delete anything.

### Migrating from Apple Reminders

If you've been tracking client work in Apple Reminders, **Settings → Import from
Apple Reminders** does a one-time migration: it scans your Reminders lists, parses
them using common conventions (`YYYY - Client - 1040`, `Client - MM/YYYY` for
bookkeeping, "Waiting on ___" hold suffixes, biweekly payroll, etc.), and shows a
**preview you can review and deselect items from** before anything is created.
Likely duplicates (matched by title against what's already in the app) are
pre-unchecked. It never modifies or deletes anything in Reminders — read-only.

---

## Requirements

- **macOS with Xcode 15 or later** (Xcode 16 recommended).
- **[XcodeGen](https://github.com/yonyz/XcodeGen)** to generate the Xcode project:
  ```sh
  brew install xcodegen
  ```
- An **Apple Developer account** (free is fine for running on your own devices; a
  paid account is needed for TestFlight / the App Store and for CloudKit on a real
  device).
- iOS/iPadOS **17.0+** on target devices.

---

## Getting started

From the repository root:

```sh
xcodegen generate      # reads project.yml, writes CPAManager.xcodeproj
open CPAManager.xcodeproj
```

> The `.xcodeproj` is generated from `project.yml` and is **git-ignored** — always
> regenerate it rather than editing it by hand. Re-run `xcodegen generate` after
> pulling changes.

Then, one-time setup in Xcode (**Signing & Capabilities** tab):

1. **Both targets** (`CPAManager` and `CPAWidgets`): pick your **Team** under
   *Signing*. Automatic signing is fine.
2. **CPAManager target** — confirm these capabilities (already declared in the
   entitlements, you just need them enabled for your team):
   - **iCloud → CloudKit**, with a container named
     `iCloud.com.gottfriedcpa.ProjectManager` (Xcode can create it).
   - **App Groups**, with `group.com.gottfriedcpa.ProjectManager`.
3. **CPAWidgets target** — enable the same **App Group**
   `group.com.gottfriedcpa.ProjectManager`.
4. Confirm the app's **Info** has **"Supports Live Activities" = YES** (set via
   `NSSupportsLiveActivities` in `project.yml`).

Pick an iPhone simulator (or your device) and **Run**.

### Changing the bundle identifier / container

The placeholders use the prefix `com.gottfriedcpa.ProjectManager`. If you use your
own, update **all four** of these so they stay in sync:

- `project.yml` — `PRODUCT_BUNDLE_IDENTIFIER` for both targets.
- `CPAManager/Entitlements/CPAManager.entitlements` — iCloud container + App Group.
- `CPAWidgets/CPAWidgets.entitlements` — App Group.
- `CPAManager/Shared/AppGroup.swift` — the `AppGroup.identifier` constant.

Then re-run `xcodegen generate`.

---

## How sync works

Data is stored with **SwiftData** and mirrored to your **private CloudKit
database** automatically (`cloudKitDatabase: .automatic`). Sign into the **same
iCloud account** on each device and your clients, projects, tasks, templates, and
time entries appear everywhere. Nothing leaves your iCloud; there is no third-party
backend.

If CloudKit isn't configured yet (e.g. no iCloud account on the simulator), the app
**falls back to a local store** so it still runs — see `CPAManagerApp.swift`. That
fallback used to be silent; **Settings → iCloud Sync** now shows whether each device
is actually "Active" or stuck on "Local Only" (and why), so you don't have to guess.

> **First-run note:** seeding runs when the local store is empty. If you install on
> a second device before the first device's data has finished syncing down, both may
> seed the default templates and you'll see duplicates. Just delete the extras (or
> use *Settings → Restore default templates* as needed).

### Sync not working?

Check **Settings → iCloud Sync on each device first** — it tells you exactly what's
going on instead of guessing:

1. **If any device shows "Local Only — not syncing"** with an error message: that
   device's SwiftData container failed to connect to CloudKit at all. The single most
   common cause, especially if you're on TestFlight: **the CloudKit schema was never
   deployed to Production** (record types only exist in the Development environment
   until you manually promote them). Fix: run the app once from Xcode in **Debug**
   (creates the schema in Development), then go to
   [icloud.developer.apple.com](https://icloud.developer.apple.com) → your
   `iCloud.com.gottfriedcpa.ProjectManager` container → **Schema** → **Deploy Schema
   to Production**. Re-upload/reinstall after.
2. **If both devices show "Active"** but data still isn't appearing on the other:
   - Confirm the **iCloud account** shown matches on both (Settings shows the raw
     account status too — "No iCloud account," "Restricted," etc. means the account
     itself is the problem, not the app).
   - On each device, go to **Settings (system) → [your name] → iCloud → Apps Using
     iCloud** (or "See All") and make sure this app is toggled **on**. A TestFlight
     install can end up with this off without ever prompting you.
   - Give it a minute and **relaunch** the app on both ends — SwiftData does an
     import pass on launch/foreground; it isn't always instant, especially for the
     very first sync between two devices.
3. Still stuck? Check **Settings → iCloud Sync → Container** matches
   `iCloud.com.gottfriedcpa.ProjectManager` on both devices — a mismatched bundle ID
   or container (e.g. one device on an older build before a rename) would put them
   in two different CloudKit containers that can never sync with each other.

---

## Project layout

```
project.yml                     XcodeGen spec (targets, capabilities, Info.plist)
CPAManager/
  App/            App entry (@main), settings keys
  Models/         SwiftData @Model types + enums (CloudKit-safe)
  Services/       WorkflowEngine, RecurrenceService, NotificationScheduler,
                  TimerController, SnapshotBuilder, SeedData, RemindersImporter,
                  InvoicePDF, KeychainStore, QBO/ (OAuth, client, sync)
  Shared/         Compiled into BOTH app & widget — Live Activity attributes,
                  App-Group dashboard snapshot, formatters, theme, DateMath
  Views/          Dashboard, Clients, Work (+ Board), Deadlines, Documents,
                  Templates, Recurring, Time, Invoices, Reports, Settings,
                  and reusable Components
  Resources/      Asset catalog (accent color; app icon)
  Entitlements/   iCloud (CloudKit) + App Group
CPAWidgets/       Widget extension: Due-Today widget + Timer Live Activity
docs/qbo-redirect/  Static HTTPS redirect page for QuickBooks OAuth (see below)
```

### Data model
`Client 1—* Project 1—* TaskItem`, `Client 1—* Document` and `Project 1—* Document`,
`WorkflowTemplate 1—* TemplateTask`, `RecurringEngagement` (links a client +
template on a schedule), `TimeEntry` (owned by a project; `invoiceID` marks it
billed), and `Invoice 1—* InvoiceLine` (owned by a client). All attributes have
defaults and all relationships are optional — the requirements for SwiftData +
CloudKit.

### Permissions the app asks for

Each is requested only the first time the relevant feature is used, with a plain-
language explanation (already wired up in `project.yml`'s Info.plist entries):

| Permission | Used for | Requested by |
|---|---|---|
| Camera | Scanning documents | Tapping "Scan Document" |
| Reminders (full access) | The one-time Reminders import | Settings → Import from Apple Reminders |
| Calendar (write-only) | Adding a single deadline | Tapping "Add to Calendar" |
| Contacts | *(none needed)* — the picker runs out-of-process | Tapping "Import from Contacts" |

---

## Connecting QuickBooks Online

This is entirely optional — invoices work fine without it, you'll just skip the
"Send to QuickBooks" button. If you want the sync, you need your own free Intuit
developer app (Matt's app talks directly to Intuit; there's no middleman server).

### 1. Create an Intuit developer app

1. Go to [developer.intuit.com](https://developer.intuit.com), sign in with your
   QuickBooks account, and create a new app (**Accounting** scope).
2. You'll get a **sandbox** Client ID/Secret immediately for testing against a fake
   company file — start there before touching real data.
3. Under the app's **Keys & OAuth** settings, you'll set a **Redirect URI** — that's
   the GitHub Pages URL from the next step.

### 2. Host the redirect page

Intuit requires an **HTTPS** redirect URI (custom URL schemes aren't accepted
directly), so this repo includes a tiny static page at `docs/qbo-redirect/index.html`
that immediately forwards back into the app. The easiest free host is GitHub Pages:

1. In your GitHub repo settings → **Pages**, set the source to the `docs/` folder
   on this branch (or `main`, once merged).
2. Your redirect URL will be something like
   `https://<your-username>.github.io/cpaprojectmanager/qbo-redirect/`.
3. Paste that **exact URL** into the Intuit app's Redirect URI field, and also into
   the app's QuickBooks settings (next step) — they must match exactly.

### 3. Connect in the app

1. In the app: **Settings → QuickBooks Online**.
2. Pick **Sandbox** (start here), and enter your Client ID, Client Secret, and the
   Redirect URL from step 2.
3. Tap **Connect to QuickBooks** — this opens a secure in-app browser
   (`ASWebAuthenticationSession`) to Intuit's login/authorize page, then returns you
   to the app automatically. Your Client ID/Secret and tokens are stored in the
   device **Keychain** only — never in code, UserDefaults, or iCloud.
4. Open an invoice and tap **Send to QuickBooks**. The app automatically creates a
   matching Customer (or reuses one by name) and an "Accounting Services" line item
   in your sandbox company the first time, then creates the invoice.
5. Once you're confident it's working, create a **second, production** Intuit app
   (or just flip the same app to production keys per Intuit's process), switch the
   Environment picker to **Production**, and reconnect.

No CFBundleURLTypes / URL-scheme registration is needed in Xcode —
`ASWebAuthenticationSession` handles the `cpamanager://` callback internally.

---

## Acceptance checklist

Run through this on your Mac to confirm everything works end-to-end:

1. `xcodegen generate` completes without errors and `CPAManager.xcodeproj` opens.
2. App **builds and launches** in an iPhone simulator; you see seeded sample data.
3. Create a **client → project → tasks**; check tasks off and watch progress update.
4. **Apply a template** to a project (or create a project *from* a template) and
   confirm tasks appear with computed due dates.
5. Use **Work → + → New Tax Return**; confirm the due date and "Awaiting Docs"
   status match (received date + 9 days, weekend-adjusted).
6. On a project, tap **Advance** a couple of times, then **Put on hold…** and
   **Take off hold** — confirm it resumes at the right stage with a new due date.
7. Toggle **Work → board icon**; drag a card to a different column on an iPad
   (or iPad simulator) and confirm the status updates.
8. **Scan a document** on a **real device** (VisionKit doesn't work in Simulator)
   and confirm it attaches and previews; also try "Choose Photo" and "Choose File".
9. Log some time, then **More → Invoices → +** to build an invoice from it; **Share
   PDF** and confirm it looks right; check the entry now shows "Billed" in Time.
10. If you've connected QuickBooks (see above), tap **Send to QuickBooks** on an
    invoice and confirm it appears in your sandbox company.
11. **Import from Contacts** on a new client, and **Add to Calendar** on a deadline.
12. If you use Apple Reminders for client work, try **Settings → Import from Apple
    Reminders** and review the preview (safe to cancel — nothing is created until
    you tap Import).
13. On a **real device**, **start the timer** on a project → a **Live Activity**
    shows on the lock screen / Dynamic Island; **stop** ends it.
14. Add the **"Due Today" widget** to the home screen; it reflects your data.
15. Install on a **second device** with the same iCloud account → data **syncs**.
16. Leave a due date for tomorrow; confirm a **local notification** is scheduled
    (allow notifications when prompted).

---

## Getting it onto TestFlight

TestFlight distribution requires a few things beyond just running on your own
device in Xcode. Do these **in order**.

> **Already on TestFlight from before?** This update added new SwiftData models
> (Document, Invoice, InvoiceLine) and fields. Before your next upload, run the app
> once in Debug so the new schema is created in Development, then **deploy it to
> Production** again — see step 4 below. Skipping this makes the next Release build
> fail to sync those new pieces.

### 0. Prerequisite: a paid Apple Developer Program account

Running the app on your own iPhone/iPad works with a **free** Apple ID. TestFlight
does not — it requires an active **Apple Developer Program membership ($99/year)**
enrolled at [developer.apple.com](https://developer.apple.com/programs/). If you
haven't enrolled yet, do that first; approval can take a few hours.

### 1. Get the code onto your Mac

```sh
git clone <this repo's URL>
cd cpaprojectmanager
git checkout claude/cpa-project-manager-k5vauq
brew install xcodegen
xcodegen generate
open CPAManager.xcodeproj
```

### 2. App icon

A placeholder app icon (a checklist card on the app's brand-blue gradient) is
already included at `CPAManager/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
and wired up in `Contents.json`, so this won't block a TestFlight upload. Swap it
for your own branding whenever you like: replace that PNG (1024×1024, RGB, no
transparency — iOS applies the corner mask) or drag a new one onto the "App Icon"
slot in Xcode's asset catalog editor.

### 3. Finish the signing setup from the main README

Do the "Getting started" steps above first (Team selected on **both** targets,
iCloud/CloudKit + App Group capabilities enabled) if you haven't already. With
**Automatically manage signing** checked, Xcode registers the bundle IDs and the
iCloud container/App Group with your developer account the first time you build.

### 4. Deploy the CloudKit schema to Production

CloudKit has two environments: **Development** (what Debug/simulator runs use)
and **Production** (what Release/Archive/TestFlight builds use). Your schema
only exists in Development until you promote it — an Archive build will fail to
sync (or throw CloudKit errors) against Production until you do this:

1. Run the app once from Xcode (Debug) so the schema is created in Development.
2. Open **[icloud.developer.apple.com](https://icloud.developer.apple.com)** →
   your `iCloud.com.gottfriedcpa.ProjectManager` container → **Schema**.
3. Click **Deploy Schema to Production** and confirm.

Repeat this any time you add/change a SwiftData model before your next TestFlight
build.

### 5. Create the app record in App Store Connect

1. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Apps**
   → **+** → **New App**.
2. Platform: iOS. Name: whatever you'd like (e.g. "CPA Manager"). Primary
   language, and **Bundle ID**: select `com.gottfriedcpa.ProjectManager` from the
   dropdown (it appears here once Xcode has registered it via step 3 — if it's
   not listed yet, build once in Xcode first, or register it manually at
   [developer.apple.com/account/resources/identifiers](https://developer.apple.com/account/resources/identifiers/list)).
3. Set a SKU (any unique string, e.g. `cpamanager1`) and create the app.

### 6. Archive and upload

1. In Xcode, select the **CPAManager** scheme and **Any iOS Device (arm64)** as
   the destination (not a simulator).
2. **Product → Archive.** The widget extension is embedded automatically since
   `project.yml` declares it as a dependency of the app target.
3. When the Organizer opens, select the archive → **Distribute App** → **App
   Store Connect** → **Upload**. Use automatic signing options unless you have a
   reason not to.
4. Wait for Apple to finish processing the build (an email arrives, and it shows
   up under **TestFlight** in App Store Connect) — usually 10–30 minutes.

### 7. Add yourself (and others) as testers

1. In App Store Connect → your app → **TestFlight** tab, the processed build
   appears. You may need to answer an **export compliance** question — the app
   sets `ITSAppUsesNonExemptEncryption = false`, so answer "No" / it should
   auto-clear.
2. Under **Internal Testing**, create a group (e.g. "Just Me"), add your own
   Apple ID (must have a role on the App Store Connect team — the account owner
   always does), and assign the build. Internal testers get access **immediately**,
   no App Review needed.
3. Install the **TestFlight** app from the App Store on your iPhone/iPad, accept
   the email invite, and install the build.
4. (Only if you later want to invite people outside your account) **External
   Testing** groups go through a brief **Beta App Review** (usually faster than
   full App Store review) before testers can install.

### Repeating for future builds

Bump `CURRENT_PROJECT_VERSION` in `project.yml` (or in Xcode's target settings)
for each new upload, re-run `xcodegen generate` if you edited `project.yml`, and
repeat step 6. Internal testers on the same group auto-see new builds.

---

## Notes & next steps

- **Notifications** are local only (no push server needed). iOS caps pending local
  notifications at 64; the scheduler keeps to the soonest ~60.
- **Document scanning** requires a real device — VisionKit's document camera isn't
  available in the iOS Simulator.
- **QuickBooks sync** is intentionally minimal (v1): it creates/reuses one Customer
  per client and one shared "Accounting Services" line item, then posts the
  invoice. It doesn't yet sync payments back, handle multiple service items/rates,
  or import anything *from* QuickBooks — all reasonable next steps if useful.
- The Apple Reminders importer covers the conventions seen in your existing lists;
  if you have reminders that don't fit the patterns (odd titles, no due date), they
  land in a generic bucket you can review and edit rather than being dropped.
- Ideas for later: a client portal / e-signature requests, recording payments
  against invoices, and pulling paid/overdue status back from QuickBooks.
