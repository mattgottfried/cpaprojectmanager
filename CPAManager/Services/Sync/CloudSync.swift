import Foundation
import SwiftData
import Observation

#if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore)
import FirebaseCore
import FirebaseAuth
#endif

/// Owns cloud sign-in and the sync engine. The app runs fine without it: with no Firebase
/// configuration file bundled, or when signed out, everything stays local.
@MainActor
@Observable
final class CloudSync {
    enum Availability: Equatable {
        /// Built without the Firebase package.
        case notCompiled
        /// No `GoogleService-Info.plist` in the app.
        case missingConfig
        case signedOut
        case signedIn
    }

    private(set) var availability: Availability
    private(set) var userEmail: String?
    private(set) var isBusy = false
    /// Last sign-in / account message for the UI.
    var message: String?
    private(set) var engine: SyncEngine?

    private let context: ModelContext
    private var authHandle: NSObjectProtocol?
    private var started = false

    init(context: ModelContext) {
        self.context = context
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore)
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            if FirebaseApp.app() == nil { FirebaseApp.configure() }
            availability = .signedOut
        } else {
            availability = .missingConfig
        }
        #else
        availability = .notCompiled
        #endif
    }

    /// A stable id for this install, so writes can be attributed to a device.
    static var deviceID: String {
        let key = "cloudSyncDeviceID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: key)
        return created
    }

    // MARK: Lifecycle

    func start() {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore)
        guard availability != .missingConfig, availability != .notCompiled, !started else { return }
        started = true
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            let uid = user?.uid
            let email = user?.email
            Task { @MainActor in self?.userChanged(uid: uid, email: email) }
        }
        #endif
    }

    private func userChanged(uid: String?, email: String?) {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore)
        engine?.stop()
        engine = nil
        userEmail = email
        guard let uid else {
            availability = .signedOut
            return
        }
        availability = .signedIn
        let backend = FirestoreBackend(uid: uid, deviceID: Self.deviceID)
        let newEngine = SyncEngine(context: context, backend: backend, ledgerStore: FileLedgerStore(userID: uid))
        engine = newEngine
        newEngine.start()
        #endif
    }

    /// Sync soon (app came to the foreground, or the user asked).
    func syncNow() {
        engine?.kick()
    }

    // MARK: Account

    func signIn(email: String, password: String) async {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore)
        await run("Signing in…") { _ = try await Auth.auth().signIn(withEmail: email, password: password) }
        #endif
    }

    func createAccount(email: String, password: String) async {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore)
        await run("Creating account…") { _ = try await Auth.auth().createUser(withEmail: email, password: password) }
        #endif
    }

    func resetPassword(email: String) async {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore)
        await run("Sending reset email…") {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        }
        if message == nil { message = "Password reset email sent." }
        #endif
    }

    func signOut() {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore)
        do {
            try Auth.auth().signOut()
            message = nil
        } catch {
            message = error.localizedDescription
        }
        #endif
    }

    private func run(_ working: String, _ work: () async throws -> Void) async {
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            try await work()
        } catch {
            message = error.localizedDescription
        }
    }
}
