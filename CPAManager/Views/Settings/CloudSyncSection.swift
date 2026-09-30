import SwiftUI

/// Settings section for cloud sync: sign in / create account, and sync status.
struct CloudSyncSection: View {
    @Environment(CloudSync.self) private var cloud

    @State private var email = ""
    @State private var password = ""
    @State private var showingResetSent = false

    var body: some View {
        Section {
            switch cloud.availability {
            case .notCompiled:
                Label("Cloud sync isn't included in this build.", systemImage: "icloud.slash")
                    .foregroundStyle(.secondary)
            case .missingConfig:
                Label("Cloud sync isn't set up", systemImage: "exclamationmark.icloud.fill")
                    .foregroundStyle(Theme.color(.caution))
                Text("This build has no Firebase configuration file, so your data stays on this device. See docs/FIRESTORE_SETUP.md.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .signedOut:
                signedOutBody
            case .signedIn:
                signedInBody
            }
        } header: {
            Text("Cloud Sync")
        } footer: {
            Text("Your data syncs between your devices through your own Firebase project. Sign in with the same account on every device. Settings and Google/QuickBooks connections still sync through iCloud.")
        }
    }

    // MARK: Signed out

    @ViewBuilder
    private var signedOutBody: some View {
        TextField("Email", text: $email)
            .emailFieldTraits()
            .noAutocapitalization()
        SecureField("Password", text: $password)
        Button {
            Task { await cloud.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password) }
        } label: {
            Label("Sign in", systemImage: "person.crop.circle.badge.checkmark")
        }
        .disabled(email.isEmpty || password.isEmpty || cloud.isBusy)
        Button {
            Task { await cloud.createAccount(email: email.trimmingCharacters(in: .whitespaces), password: password) }
        } label: {
            Label("Create account", systemImage: "person.crop.circle.badge.plus")
        }
        .disabled(email.isEmpty || password.count < 6 || cloud.isBusy)
        Button("Forgot password") {
            Task { await cloud.resetPassword(email: email.trimmingCharacters(in: .whitespaces)) }
        }
        .font(.footnote)
        .disabled(email.isEmpty || cloud.isBusy)
        if let message = cloud.message {
            Text(message).font(.footnote).foregroundStyle(Theme.color(.bad)).textSelection(.enabled)
        }
    }

    // MARK: Signed in

    @ViewBuilder
    private var signedInBody: some View {
        LabeledContent("Account", value: cloud.userEmail ?? "Signed in")

        if let engine = cloud.engine {
            statusRow(engine)

            if engine.blockedDeletionCount > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(engine.blockedDeletionCount) records are missing from this device. If you didn't delete them, restore them from the cloud.")
                        .font(.footnote)
                    HStack {
                        Button("Restore from cloud") { engine.restoreDeletedFromCloud() }
                        Button("Delete everywhere", role: .destructive) { engine.confirmDeletions() }
                    }
                    .buttonStyle(.bordered)
                }
            }

            if engine.pendingUploads > 0 {
                LabeledContent("Waiting to upload", value: "\(engine.pendingUploads)")
                    .font(.caption)
            }
            if engine.oversizedFileCount > 0 {
                Label("\(engine.oversizedFileCount) file\(engine.oversizedFileCount == 1 ? " is" : "s are") too large to sync (over about 0.8 MB). The record syncs, the file stays on the device that added it. Keep big files in Google Drive and link them.", systemImage: "doc.badge.ellipsis")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Last sent") { dateValue(engine.lastPushDate) }
            LabeledContent("Last received") { dateValue(engine.lastPullDate) }
        }

        Button {
            cloud.syncNow()
        } label: {
            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
        }
        NavigationLink {
            SyncHealthView()
        } label: {
            Label("Sync health & duplicates", systemImage: "stethoscope")
        }

        Button("Sign out", role: .destructive) { cloud.signOut() }
    }

    @ViewBuilder
    private func statusRow(_ engine: SyncEngine) -> some View {
        switch engine.phase {
        case .stopped, .connecting:
            Label("Connecting…", systemImage: "icloud")
                .foregroundStyle(.secondary)
        case .syncing:
            Label("Syncing…", systemImage: "arrow.triangle.2.circlepath.icloud")
                .foregroundStyle(Theme.color(.info))
        case .idle:
            Label("Up to date", systemImage: "checkmark.icloud.fill")
                .foregroundStyle(Theme.color(.good))
        case .attention:
            Label("Needs your attention", systemImage: "exclamationmark.icloud.fill")
                .foregroundStyle(Theme.color(.caution))
        case .error(let text):
            VStack(alignment: .leading, spacing: 4) {
                Label("Sync problem", systemImage: "xmark.icloud.fill")
                    .foregroundStyle(Theme.color(.bad))
                Text(text).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func dateValue(_ date: Date?) -> some View {
        if let date {
            Text(date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
        } else {
            Text("Not yet").foregroundStyle(.secondary)
        }
    }
}
