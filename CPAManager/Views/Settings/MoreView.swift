import SwiftUI

/// The "More" tab: navigation hub for templates, recurring work, time, and settings.
struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        TemplatesListView()
                    } label: {
                        Label("Templates", systemImage: "square.stack.3d.up.fill")
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
