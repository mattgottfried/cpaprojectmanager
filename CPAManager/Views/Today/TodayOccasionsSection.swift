import SwiftUI
import SwiftData

/// Birthdays and client anniversaries from today through the next few days. Sending a
/// note (or dismissing) acknowledges it for the year so it stops showing.
struct TodayOccasionsSection: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @AppStorage(SettingsKeys.firmName) private var firmName = ""

    let clients: [Client]
    var lookAheadDays = 3

    private var occasions: [Occasion] {
        let sources = clients.map {
            OccasionSource(
                clientID: $0.id, clientName: $0.displayName,
                birthday: $0.birthday, anniversary: $0.anniversary,
                birthdayAckYear: $0.birthdayAckYear, anniversaryAckYear: $0.anniversaryAckYear,
                isActive: $0.status != .inactive
            )
        }
        return Occasions.upcoming(sources, withinDays: lookAheadDays).filter { !$0.acknowledged }
    }

    var body: some View {
        let items = occasions
        if !items.isEmpty {
            Section {
                ForEach(items) { occasion in
                    row(occasion)
                }
            } header: {
                Label("Dates to remember", systemImage: "gift.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.color(.info))
                    .textCase(nil)
            }
        }
    }

    private func row(_ occasion: Occasion) -> some View {
        HStack(spacing: 12) {
            StatusTile(systemImage: occasion.kind.systemImage, state: .info)
            VStack(alignment: .leading, spacing: 2) {
                Text(Occasions.title(for: occasion)).font(.body.weight(.semibold))
                Text(occasion.daysAway == 0 ? "Today" : occasion.daysAway == 1 ? "Tomorrow" : "In \(occasion.daysAway) days")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                acknowledge(occasion, logNote: true)
            } label: {
                Image(systemName: "checkmark.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Mark sent")
        }
        .rowCard()
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing) {
            Button("Dismiss") { acknowledge(occasion, logNote: false) }.tint(.gray)
        }
        .contextMenu {
            if let client = clients.first(where: { $0.id == occasion.clientID }),
               let url = MailtoBuilder.url(
                to: client.email,
                subject: occasion.kind == .birthday ? "Happy birthday!" : "Thank you!",
                body: "Hi \(client.displayName.split(separator: " ").first.map(String.init) ?? client.displayName),\n\n"
            ) {
                Button { openURL(url) } label: { Label("Write an email", systemImage: "envelope") }
            }
        }
    }

    private func acknowledge(_ occasion: Occasion, logNote: Bool) {
        guard let client = clients.first(where: { $0.id == occasion.clientID }) else { return }
        let year = Calendar.current.component(.year, from: occasion.date)
        switch occasion.kind {
        case .birthday:    client.birthdayAckYear = year
        case .anniversary: client.anniversaryAckYear = year
        }
        if logNote {
            context.insert(Interaction(kind: .note, summary: "Sent \(occasion.kind.label.lowercased()) wishes", client: client))
        }
        try? context.save()
    }
}
