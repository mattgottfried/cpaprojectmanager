import SwiftUI

/// Tax-season snapshot at the top of Today: days to the deadline, open returns by stage,
/// and the loose ends (no return started, extensions, documents still owed).
struct TaxSeasonCard: View {
    let projects: [Project]
    let clients: [Client]
    let docRequests: [DocumentRequest]
    @AppStorage(SettingsKeys.taxSeasonMode) private var modeRaw = TaxSeasonMode.auto.rawValue
    @Environment(AppRouter.self) private var router

    private var mode: TaxSeasonMode { TaxSeasonMode(rawValue: modeRaw) ?? .auto }

    private var summary: TaxSeasonSummary {
        let taxYear = TaxSeason.workingTaxYear()
        let seasonProjects = projects.map {
            SeasonProject(statusRaw: $0.statusRaw, taxYear: $0.taxYear, isTaxReturn: $0.serviceType == .taxReturn)
        }
        let seasonClients = clients.map { client in
            SeasonClient(
                isActive: client.status == .active,
                extensionYears: client.extensionYears,
                hasReturnForYear: client.projectList.contains { $0.serviceType == .taxReturn && $0.taxYear == taxYear }
            )
        }
        return TaxSeason.summary(
            projects: seasonProjects, clients: seasonClients,
            documentsOutstanding: docRequests.filter { !$0.isReceived }.count
        )
    }

    var body: some View {
        if TaxSeason.isActive(mode: mode) {
            let s = summary
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Tax season", systemImage: "calendar.badge.clock")
                        .font(.headline)
                        .foregroundStyle(Theme.color(.alert))
                    Spacer()
                    Text("\(s.daysToDeadline) day\(s.daysToDeadline == 1 ? "" : "s") to \(Format.shortDate.string(from: s.deadline))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(s.daysToDeadline <= 14 ? Theme.color(.bad) : .primary)
                }

                if s.stages.isEmpty {
                    Text("No open \(String(s.taxYear)) returns.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(s.stages) { stage in
                                CapsuleBadge(text: "\(StatusFlow.taxReturn.label(stage.status)) \(stage.count)", systemImage: stage.status.systemImage, state: .info)
                            }
                        }
                    }
                }

                HStack(spacing: 14) {
                    metric("\(s.noReturnStarted)", "not started")
                    metric("\(s.onExtension)", "on extension")
                    metric("\(s.documentsOutstanding)", "docs owed")
                    metric("\(s.openReturns)", "open returns")
                }
            }
            .rowCard()
            .contentShape(Rectangle())
            .onTapGesture { router.go(to: .work) }
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens Work")
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.title3.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
