import Foundation

#if canImport(FirebaseFirestore)
import FirebaseFirestore

/// Cloud Firestore as the sync backend. Layout: `users/{uid}/records/{collection}~{uuid}`,
/// each document holding the record as JSON text (`j`), its collection (`c`), a server
/// timestamp (`u`) and the writing device (`d`). Security rules limit each user to their own
/// `users/{uid}` tree (see `firestore.rules`).
final class FirestoreBackend: SyncBackend {
    private let uid: String
    private let deviceID: String
    private var registration: ListenerRegistration?

    init(uid: String, deviceID: String) {
        self.uid = uid
        self.deviceID = deviceID
    }

    private var records: CollectionReference {
        Firestore.firestore().collection("users").document(uid).collection("records")
    }

    func start(
        onBatch: @escaping @MainActor ([SyncRemoteChange], Bool) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) {
        registration?.remove()
        var isFirst = true
        registration = records.addSnapshotListener { snapshot, error in
            if let error {
                let message = error.localizedDescription
                Task { @MainActor in onError(message) }
                return
            }
            guard let snapshot else { return }

            var changes: [SyncRemoteChange] = []
            for change in snapshot.documentChanges {
                let document = change.document
                // Our own write that the server hasn't confirmed yet — we already have it.
                if document.metadata.hasPendingWrites { continue }
                guard let key = SyncKey(documentID: document.documentID) else { continue }
                if change.type == .removed {
                    changes.append(SyncRemoteChange(key: key, entry: nil))
                } else if let json = document.data()["j"] as? String {
                    changes.append(SyncRemoteChange(key: key, entry: SyncEntry(key: key, json: json)))
                }
            }
            let initial = isFirst
            isFirst = false
            let delivered = changes
            Task { @MainActor in onBatch(delivered, initial) }
        }
    }

    func stop() {
        registration?.remove()
        registration = nil
    }

    func write(upserts: [SyncEntry], deletes: [SyncKey]) async throws {
        let db = Firestore.firestore()
        let batch = db.batch()
        for entry in upserts {
            batch.setData(
                [
                    "c": entry.key.collection.rawValue,
                    "j": entry.json,
                    "u": FieldValue.serverTimestamp(),
                    "d": deviceID,
                ],
                forDocument: records.document(entry.key.documentID)
            )
        }
        for key in deletes {
            batch.deleteDocument(records.document(key.documentID))
        }
        try await batch.commit()
    }
}
#endif
