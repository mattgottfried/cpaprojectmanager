import SwiftUI
import EventKit
import EventKitUI

/// A single deadline being handed off to the system "Add Event" sheet.
struct CalendarEventRequest: Identifiable {
    let id = UUID()
    let title: String
    let date: Date
    var notes: String = ""
}

/// Presents the system "Add Event" sheet, pre-filled with a title and date.
/// `EKEventEditViewController` prompts for calendar access itself the first
/// time it's used — no separate permission request needed in-app.
struct CalendarEventView: UIViewControllerRepresentable {
    let request: CalendarEventRequest
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = request.title
        event.notes = request.notes
        event.startDate = request.date
        event.endDate = request.date.addingTimeInterval(3600)
        event.isAllDay = false

        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }

        func eventEditViewController(
            _ controller: EKEventEditViewController,
            didCompleteWith action: EKEventEditViewAction
        ) {
            dismiss()
        }
    }
}
