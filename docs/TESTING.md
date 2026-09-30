# Device test checklist

Run through this on a real iPhone (and iPad/Mac if you use them) before sending a build
to testers. The app has no automated UI tests and the cloud session cannot compile, so
this list is the safety net.

## Every build
- [ ] Fresh install launches; onboarding appears once and never again.
- [ ] Update over the previous build: launches, data still there, no schema error.
- [ ] Today loads; add a task by typing; swipe done / tomorrow.
- [ ] Create a client, a project and a task; kill and relaunch — all still there.
- [ ] Settings → Data Health reports "consistent".

## Sync (two devices signed in to the same iCloud)
- [ ] Add a client on device A → appears on B within a minute.
- [ ] Change a setting (e.g. firm name) on A → appears on B.
- [ ] Create an invoice on each device while offline, reconnect → Data Health flags the
      duplicate number and "Renumber" fixes it.
- [ ] Install on a brand-new device: default templates are not duplicated (or Data Health
      removes the duplicates).

## Features (tick the ones the build touched)
- [ ] Pipelines: create, assign, advance, drag on board; entry tasks appear once.
- [ ] Recurring work: bulk setup, naming preview, end date, skip/pause.
- [ ] Letters/emails: PDF has signature block; "Track as sent" shows on the document;
      Today nudges after the chosen days; "Mark signed" clears it.
- [ ] Upload link: set in Settings; appears in the document-request email.
- [ ] Quotes: create, PDF, convert to invoice (only once); fee schedule picker.
- [ ] Client rate override and flat-fee flag change what a new timer bills.
- [ ] Task details: subtasks tick, blocked task hidden on Today until blocker is done.
- [ ] Import: sample clients CSV and time CSV preview counts look right.
- [ ] Tax-season card shows in season and can be turned off.
- [ ] Time rounding changes invoice hours; long-timer notification arrives.
- [ ] Backup → restore an older backup file into a fresh install.

## Mac / iPad
- [ ] ⌘K search, ⌘N new task, ⌥⌘N new window; each window navigates independently.
- [ ] iPad: open a second window (Split View / Stage Manager) and resize.

## Accessibility
- [ ] VoiceOver: every icon-only button is announced sensibly.
- [ ] Largest Dynamic Type size: Today and Client screens stay usable.
