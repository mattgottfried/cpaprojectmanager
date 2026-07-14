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
| **Dashboard** | Overdue / due-today / open-work counts, an active-timer banner, "coming up" and "in progress" lists. |
| **Clients** | Searchable CRM with entity type (1040, 1120-S, 1065, 1120, 1041, 990), status, notes, and tap-to-call / text / email. |
| **Work** | Projects (e.g. "Smith 2025 — 1040 Individual Return") broken into checkable tasks, with status, priority, due date, and progress. |
| **Deadlines** | Everything due, grouped **Overdue / Today / This Week / Later**, plus a reference list of standard US filing dates. |
| **Templates** | Reusable engagement checklists. Instantiating one creates a project with tasks whose due dates are computed from each step's day-offset. |
| **Recurring work** | Monthly bookkeeping, quarterly estimates, payroll, etc. — auto-generates a project from a template when its lead-time window opens, then advances the schedule. |
| **Time & billing** | Start/stop timer (also a Live Activity), a running billable total for the month, and a time log. |

The app **seeds itself on first launch** with a few sample clients and five default
templates (1040, 1120-S, Monthly Bookkeeping, Quarterly Estimates, Payroll Run) so
it isn't empty. You can edit or delete anything.

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
**falls back to a local store** so it still runs — see `CPAManagerApp.swift`.

> **First-run note:** seeding runs when the local store is empty. If you install on
> a second device before the first device's data has finished syncing down, both may
> seed the default templates and you'll see duplicates. Just delete the extras (or
> use *Settings → Restore default templates* as needed).

---

## Project layout

```
project.yml                     XcodeGen spec (targets, capabilities, Info.plist)
CPAManager/
  App/            App entry (@main), settings keys
  Models/         SwiftData @Model types + enums (CloudKit-safe)
  Services/       WorkflowEngine, RecurrenceService, NotificationScheduler,
                  TimerController, SnapshotBuilder, SeedData
  Shared/         Compiled into BOTH app & widget — Live Activity attributes,
                  App-Group dashboard snapshot, formatters, theme
  Views/          Dashboard, Clients, Work, Deadlines, Templates, Recurring,
                  Time, Settings, and reusable Components
  Resources/      Asset catalog (accent color; placeholder app icon)
  Entitlements/   iCloud (CloudKit) + App Group
CPAWidgets/       Widget extension: Due-Today widget + Timer Live Activity
```

### Data model
`Client 1—* Project 1—* TaskItem`, plus `WorkflowTemplate 1—* TemplateTask`,
`RecurringEngagement` (links a client + template on a schedule), and `TimeEntry`
(owned by a project). All attributes have defaults and all relationships are
optional — the requirements for SwiftData + CloudKit.

---

## Acceptance checklist

Run through this on your Mac to confirm everything works end-to-end:

1. `xcodegen generate` completes without errors and `CPAManager.xcodeproj` opens.
2. App **builds and launches** in an iPhone simulator; you see seeded sample data.
3. Create a **client → project → tasks**; check tasks off and watch progress update.
4. **Apply a template** to a project (or create a project *from* a template) and
   confirm tasks appear with computed due dates.
5. On a **real device**, **start the timer** on a project → a **Live Activity**
   shows on the lock screen / Dynamic Island; **stop** ends it.
6. Add the **"Due Today" widget** to the home screen; it reflects your data.
7. Install on a **second device** with the same iCloud account → data **syncs**.
8. Leave a due date for tomorrow; confirm a **local notification** is scheduled
   (allow notifications when prompted).

---

## Getting it onto TestFlight

TestFlight distribution requires a few things beyond just running on your own
device in Xcode. Do these **in order**.

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
- Ideas for later: document storage, client portal / e-signature, invoicing &
  payments, and QuickBooks import — the model layer is structured to grow into these.
