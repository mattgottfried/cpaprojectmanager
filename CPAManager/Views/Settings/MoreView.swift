import SwiftUI

/// The "More" tab: navigation hub for templates, recurring work, time, and settings.
struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        LeadsView(embedded: true)
                    } label: {
                        Label("Leads", systemImage: "funnel.fill")
                    }
                    NavigationLink {
                        WeeklyReviewView(embedded: true)
                    } label: {
                        Label("Weekly Review", systemImage: "checkmark.seal.fill")
                    }
                    NavigationLink {
                        ActivityFeedView(embedded: true)
                    } label: {
                        Label("Activity", systemImage: "clock.arrow.circlepath")
                    }
                    NavigationLink {
                        DeadlinesView(embedded: true)
                    } label: {
                        Label("Deadlines", systemImage: "calendar")
                    }
                    NavigationLink {
                        ExtensionTrackerView()
                    } label: {
                        Label("Extensions", systemImage: "calendar.badge.clock")
                    }
                    NavigationLink {
                        DashboardView(embedded: true)
                    } label: {
                        Label("Firm Overview", systemImage: "house.fill")
                    }
                    NavigationLink {
                        TemplatesListView()
                    } label: {
                        Label("Templates", systemImage: "square.stack.3d.up.fill")
                    }
                    NavigationLink {
                        QuotesListView()
                    } label: {
                        Label("Quotes", systemImage: "doc.plaintext")
                    }
                    NavigationLink {
                        FeeScheduleView()
                    } label: {
                        Label("Fee Schedule", systemImage: "tag")
                    }
                    NavigationLink {
                        ImportView()
                    } label: {
                        Label("Import from CSV", systemImage: "square.and.arrow.down")
                    }
                    NavigationLink {
                        DataHealthView()
                    } label: {
                        Label("Data Health", systemImage: "stethoscope")
                    }
                    NavigationLink {
                        HelpView()
                    } label: {
                        Label("Help & Tips", systemImage: "questionmark.circle.fill")
                    }
                    NavigationLink {
                        TemplateLibraryView()
                    } label: {
                        Label("Letters & Emails", systemImage: "doc.richtext")
                    }
                    NavigationLink {
                        PipelinesListView(embedded: true)
                    } label: {
                        Label("Pipelines", systemImage: "rectangle.split.3x1.fill")
                    }
                    NavigationLink {
                        RecurringListView()
                    } label: {
                        Label("Recurring Work", systemImage: "arrow.triangle.2.circlepath")
                    }
                    NavigationLink {
                        TimeLogView()
                    } label: {
                        Label("Time & Billing", systemImage: "clock.fill")
                    }
                    NavigationLink {
                        InvoicesListView()
                    } label: {
                        Label("Invoices", systemImage: "doc.text.image.fill")
                    }
                    NavigationLink {
                        RecurringInvoicesView()
                    } label: {
                        Label("Recurring Invoices", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                    }
                    NavigationLink {
                        ExpensesView()
                    } label: {
                        Label("Expenses", systemImage: "creditcard.fill")
                    }
                    NavigationLink {
                        ReportsView()
                    } label: {
                        Label("Reports", systemImage: "chart.bar.fill")
                    }
                }

                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                }
            }
            .navigationTitle("More")
        }
    }
}
