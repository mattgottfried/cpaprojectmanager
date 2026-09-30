import SwiftUI

/// Searchable in-app help, plus today's tip.
struct HelpView: View {
    @State private var query = ""
    @AppStorage(SettingsKeys.hasOnboarded) private var hasOnboarded = false
    @State private var showingWalkthrough = false

    private var results: [HelpTopic] {
        query.trimmingCharacters(in: .whitespaces).isEmpty ? HelpCatalog.topics : HelpCatalog.search(query)
    }

    var body: some View {
        GroupedList {
            if query.isEmpty {
                Section {
                    Label(Tips.tip(forDay: .now), systemImage: "lightbulb.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.color(.info))
                } header: {
                    Text("Tip of the day")
                }
            }

            Section {
                ForEach(results) { topic in
                    NavigationLink {
                        HelpTopicView(topic: topic)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(topic.title)
                                Text(topic.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        } icon: {
                            Image(systemName: topic.systemImage)
                        }
                    }
                }
                if results.isEmpty {
                    Text("Nothing matches “\(query)”.").foregroundStyle(.secondary)
                }
            }

            Section {
                Button { showingWalkthrough = true } label: {
                    Label("Replay the welcome walkthrough", systemImage: "hand.wave.fill")
                }
            }
        }
        .navigationTitle("Help & Tips")
        .searchable(text: $query, prompt: "Search help")
        .sheet(isPresented: $showingWalkthrough) { OnboardingView(replay: true) }
    }
}

struct HelpTopicView: View {
    let topic: HelpTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label(topic.title, systemImage: topic.systemImage)
                    .font(.title3.bold())
                Text(topic.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Divider()
                Text(topic.body)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(topic.title)
        .inlineNavigationTitle()
    }
}

/// Dismissible "tip of the day" card for the top of Today.
struct TipCard: View {
    @AppStorage("lastDismissedTipDay") private var lastDismissedDay = 0.0
    @AppStorage("showTips") private var showTips = true

    private var dayKey: Double { Calendar.current.startOfDay(for: .now).timeIntervalSince1970 }

    var body: some View {
        if showTips && lastDismissedDay != dayKey {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lightbulb.fill").foregroundStyle(Theme.color(.info))
                Text(Tips.tip(forDay: .now))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button { lastDismissedDay = dayKey } label: {
                    Image(systemName: "xmark").font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss tip")
            }
            .rowCard()
        }
    }
}
