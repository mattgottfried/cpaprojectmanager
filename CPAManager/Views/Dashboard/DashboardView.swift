import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(TimerController.self) private var timer
    @Query private var projects: [Project]
    @Query private var tasks: [TaskItem]
    @State private var showingNewTaxReturn = false
    /// True when pushed from another stack (e.g. More) so it doesn't nest a second
    /// NavigationStack.
    var embedded = false

    private var agenda: [AgendaItem] { Agenda.items(projects: projects, tasks: tasks) }

    private var openProjectCount: Int { projects.filter { !$0.status.isComplete }.count }
    private var overdueCount: Int { agenda.filter { Agenda.bucket(for: $0.dueDate) == "Overdue" }.count }
    private var dueTodayCount: Int { agenda.filter { Agenda.bucket(for: $0.dueDate) == "Today" }.count }
    private var inProgress: [Project] { projects.filter { $0.status == .inProgress } }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 0..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    private var content: some View {
        Group {
            ScrollView {
                VStack(spacing: 16) {
                    if timer.isRunning {
                        TimerCard()
                    }

                    quickActions

                    statGrid

                    dueSoonCard

                    if !inProgress.isEmpty {
                        inProgressCard
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(greeting)
            .navigationDestination(for: Project.self) { ProjectDetailView(project: $0) }
            .sheet(isPresented: $showingNewTaxReturn) { NewTaxReturnView() }
        }
    }

    private var quickActions: some View {
        Button {
            showingNewTaxReturn = true
        } label: {
            Label("New Tax Return", systemImage: "doc.badge.plus")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.brand)
    }

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(value: "\(overdueCount)", label: "Overdue", systemImage: "exclamationmark.triangle.fill", color: overdueCount > 0 ? .red : Theme.brand)
            StatCard(value: "\(dueTodayCount)", label: "Due today", systemImage: "calendar.badge.clock", color: dueTodayCount > 0 ? .orange : Theme.brand)
            StatCard(value: "\(openProjectCount)", label: "Open work", systemImage: "checklist", color: Theme.brand)
        }
    }

    private var dueSoonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Coming up")
                .font(.headline)

            let upcoming = Array(agenda.prefix(6))
            if upcoming.isEmpty {
                Text("Nothing due. You're all caught up.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(upcoming) { item in
                    agendaRow(item)
                    if item.id != upcoming.last?.id { Divider() }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func agendaRow(_ item: AgendaItem) -> some View {
        if let project = item.project {
            NavigationLink(value: project) { agendaRowContent(item) }
                .buttonStyle(.plain)
        } else {
            agendaRowContent(item)
        }
    }

    private func agendaRowContent(_ item: AgendaItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            DueDatePill(date: item.dueDate, isComplete: item.isComplete)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var inProgressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("In progress")
                .font(.headline)
            ForEach(inProgress.prefix(5)) { project in
                NavigationLink(value: project) {
                    HStack {
                        ServiceTypeIcon(serviceType: project.serviceType, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.title).font(.subheadline.weight(.medium)).lineLimit(1)
                            Text(project.clientName).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(project.progress * 100))%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
