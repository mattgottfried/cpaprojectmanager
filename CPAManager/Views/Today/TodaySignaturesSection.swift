import SwiftUI
import SwiftData

/// Letters and quotes sent for signature that are still unsigned after your nudge delay.
struct TodaySignaturesSection: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @AppStorage(SettingsKeys.signatureChaseDays) private var chaseDays = 3
    @Query(filter: #Predicate<Document> { $0.signatureStatusRaw == "sent" }) private var sent: [Document]

    private var awaiting: [AwaitingSignature] {
        SignatureTracking.awaiting(
            sent.map {
                SignatureCandidate(
                    id: $0.id, title: $0.displayName, clientID: $0.client?.id,
                    clientName: $0.client?.displayName ?? "", statusRaw: $0.signatureStatusRaw, sentAt: $0.signatureSentAt
                )
            },
            chaseDays: chaseDays
        )
    }

    var body: some View {
        let items = awaiting
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    HStack(spacing: 12) {
                        StatusTile(systemImage: "signature", state: .caution)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.body.weight(.semibold)).lineLimit(2)
                            Text("\(item.clientName.isEmpty ? "No client" : item.clientName) · unsigned \(item.daysWaiting) day\(item.daysWaiting == 1 ? "" : "s")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Button { markSigned(item.id) } label: { Image(systemName: "checkmark.seal") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Mark signed")
                    }
                    .rowCard()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let clientID = item.clientID { router.open(.client(clientID)) }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            } header: {
                Label("Awaiting signature", systemImage: "signature")
                    .font(.headline)
                    .foregroundStyle(Theme.color(.caution))
                    .textCase(nil)
            }
        }
    }

    private func markSigned(_ id: UUID) {
        guard let document = sent.first(where: { $0.id == id }) else { return }
        document.signatureStatus = .signed
        document.signedAt = .now
        try? context.save()
    }
}
