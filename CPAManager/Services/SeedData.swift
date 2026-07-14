import Foundation
import SwiftData

/// First-run content: standard engagement templates plus a couple of sample clients
/// so the app isn't empty on first launch. Seeds only when the store is empty.
enum SeedData {

    static func seedIfNeeded(context: ModelContext) {
        let templateCount = (try? context.fetchCount(FetchDescriptor<WorkflowTemplate>())) ?? 0
        if templateCount == 0 {
            seedTemplates(context: context)
        }

        let clientCount = (try? context.fetchCount(FetchDescriptor<Client>())) ?? 0
        if clientCount == 0 {
            seedSampleClients(context: context)
        }

        try? context.save()
    }

    /// Re-add the default templates (used by the Settings "Restore default templates"
    /// action). Does not remove existing ones.
    static func restoreDefaultTemplates(context: ModelContext) {
        seedTemplates(context: context)
        try? context.save()
    }

    // MARK: Templates

    private static func seedTemplates(context: ModelContext) {
        for spec in defaultTemplates {
            let template = WorkflowTemplate(
                name: spec.name,
                detail: spec.detail,
                serviceType: spec.serviceType,
                defaultDurationDays: spec.durationDays
            )
            context.insert(template)
            for (index, step) in spec.steps.enumerated() {
                let task = TemplateTask(
                    title: step.title,
                    sortIndex: index,
                    dayOffset: step.dayOffset,
                    template: template
                )
                context.insert(task)
            }
        }
    }

    private struct Step { let title: String; let dayOffset: Int }
    private struct TemplateSpec {
        let name: String
        let detail: String
        let serviceType: ServiceType
        let durationDays: Int
        let steps: [Step]
    }

    private static let defaultTemplates: [TemplateSpec] = [
        TemplateSpec(
            name: "1040 Individual Return",
            detail: "Standard individual income tax return workflow.",
            serviceType: .taxReturn,
            durationDays: 45,
            steps: [
                Step(title: "Send engagement letter & organizer", dayOffset: 0),
                Step(title: "Collect source documents (W-2, 1099s)", dayOffset: 7),
                Step(title: "Prepare return", dayOffset: 20),
                Step(title: "Internal review", dayOffset: 28),
                Step(title: "Send to client for e-signature (Form 8879)", dayOffset: 32),
                Step(title: "E-file return", dayOffset: 40),
                Step(title: "Deliver final copy & invoice", dayOffset: 42),
            ]
        ),
        TemplateSpec(
            name: "1120-S S-Corp Return",
            detail: "S-Corporation return including shareholder K-1s.",
            serviceType: .taxReturn,
            durationDays: 45,
            steps: [
                Step(title: "Engagement letter & document request", dayOffset: 0),
                Step(title: "Collect trial balance & financials", dayOffset: 7),
                Step(title: "Prepare return & K-1s", dayOffset: 21),
                Step(title: "Internal review", dayOffset: 30),
                Step(title: "Client review & signature", dayOffset: 35),
                Step(title: "E-file 1120-S", dayOffset: 42),
                Step(title: "Distribute K-1s & invoice", dayOffset: 44),
            ]
        ),
        TemplateSpec(
            name: "Monthly Bookkeeping",
            detail: "Recurring monthly close for bookkeeping clients.",
            serviceType: .bookkeeping,
            durationDays: 15,
            steps: [
                Step(title: "Import bank & credit card transactions", dayOffset: 2),
                Step(title: "Categorize transactions", dayOffset: 5),
                Step(title: "Reconcile accounts", dayOffset: 8),
                Step(title: "Review financial statements", dayOffset: 11),
                Step(title: "Send monthly reports to client", dayOffset: 14),
            ]
        ),
        TemplateSpec(
            name: "Quarterly Estimated Taxes",
            detail: "Quarterly estimated tax calculation and payment.",
            serviceType: .taxReturn,
            durationDays: 20,
            steps: [
                Step(title: "Gather year-to-date income", dayOffset: 3),
                Step(title: "Calculate estimated payments", dayOffset: 7),
                Step(title: "Send vouchers / payment instructions", dayOffset: 10),
                Step(title: "Confirm payment made", dayOffset: 18),
            ]
        ),
        TemplateSpec(
            name: "Payroll Run",
            detail: "Standard payroll processing cycle.",
            serviceType: .payroll,
            durationDays: 5,
            steps: [
                Step(title: "Collect hours & employee changes", dayOffset: 0),
                Step(title: "Process payroll", dayOffset: 2),
                Step(title: "Submit tax deposits", dayOffset: 3),
                Step(title: "Distribute pay stubs", dayOffset: 4),
            ]
        ),
    ]

    // MARK: Sample clients

    private static func seedSampleClients(context: ModelContext) {
        let smith = Client(
            name: "John & Mary Smith",
            entityType: .individual1040,
            status: .active,
            email: "smith.family@example.com",
            phone: "(555) 201-3382",
            notes: "Longtime 1040 clients. Two dependents; itemizes."
        )
        let acme = Client(
            name: "Acme Consulting LLC",
            company: "Acme Consulting LLC",
            entityType: .sCorp1120S,
            status: .active,
            email: "owner@acme.example.com",
            phone: "(555) 447-9910",
            notes: "S-Corp, monthly bookkeeping + quarterly estimates."
        )
        let bright = Client(
            name: "Bright Futures Foundation",
            company: "Bright Futures Foundation",
            entityType: .nonProfit990,
            status: .prospect,
            email: "director@brightfutures.example.org",
            notes: "Prospect — needs 990 and bookkeeping cleanup."
        )
        context.insert(smith)
        context.insert(acme)
        context.insert(bright)
    }
}
