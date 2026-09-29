import SwiftUI
import SwiftData

/// Pushed from the More tab. Manages reusable engagement checklists.
struct TemplatesListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkflowTemplate.name) private var templates: [WorkflowTemplate]
    @State private var editingTemplate: WorkflowTemplate?
    @State private var showingNew = false

    var body: some View {
        List {
            if templates.isEmpty {
                ContentUnavailableView {
                    Label("No templates yet", systemImage: "square.stack.3d.up")
                } description: {
                    Text("Templates are reusable checklists for engagements like a 1040 or monthly bookkeeping.")
                } actions: {
                    Button("New template") { showingNew = true }.buttonStyle(.borderedProminent)
                }
                .cardListRow()
            }
            ForEach(templates) { template in
                Button {
                    editingTemplate = template
                } label: {
                    HStack(spacing: 12) {
                        ServiceTypeIcon(serviceType: template.serviceType, size: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(template.name)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text("\(template.taskList.count) steps · \(template.defaultDurationDays)-day turnaround")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .rowCard()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(template.name)
                    .accessibilityValue("\(template.taskList.count) steps, \(template.defaultDurationDays)-day turnaround")
                    .accessibilityHint("Opens the template")
                }
                .buttonStyle(.plain)
                .cardListRow()
            }
            .onDelete(perform: delete)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.appGroupedBackground)
        .navigationTitle("Templates")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingNew) { TemplateFormView() }
        .sheet(item: $editingTemplate) { TemplateFormView(template: $0) }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets { context.delete(templates[index]) }
        try? context.save()
    }
}

/// Reusable sheet for picking a template (used by "Apply template").
struct TemplatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkflowTemplate.name) private var templates: [WorkflowTemplate]
    var onSelect: (WorkflowTemplate) -> Void

    var body: some View {
        NavigationStack {
            List {
                if templates.isEmpty {
                    Text("No templates yet.").foregroundStyle(.secondary)
                }
                ForEach(templates) { template in
                    Button {
                        onSelect(template)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            ServiceTypeIcon(serviceType: template.serviceType, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name).foregroundStyle(.primary)
                                Text("\(template.taskList.count) tasks")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Choose Template")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
