import SwiftUI
import EventKit

/// A single deadline being handed off to the calendar.
struct CalendarEventRequest: Identifiable {
    let id = UUID()
    let title: String
    let date: Date
    var notes: String = ""
}

#if os(iOS)
import EventKitUI

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
#else
import AppKit

/// macOS has no embeddable "Add Event" sheet, so this writes a one-event `.ics` file
/// and opens it — Calendar then shows its standard "Add to Calendar" dialog.
struct CalendarEventView: View {
    let request: CalendarEventRequest
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ProgressView("Opening Calendar…")
            .padding(30)
            .task {
                if let url = ICSFile.write(request) { NSWorkspace.shared.open(url) }
                dismiss()
            }
    }
}

enum ICSFile {
    static func write(_ request: CalendarEventRequest) -> URL? {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        stamp.timeZone = TimeZone(identifier: "UTC")
        stamp.locale = Locale(identifier: "en_US_POSIX")

        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: ";", with: "\\;")
                .replacingOccurrences(of: ",", with: "\\,")
                .replacingOccurrences(of: "\n", with: "\\n")
        }

        let ics = [
            "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//CPA Manager//EN", "BEGIN:VEVENT",
            "UID:\(request.id.uuidString)@cpamanager",
            "DTSTAMP:\(stamp.string(from: .now))",
            "DTSTART:\(stamp.string(from: request.date))",
            "DTEND:\(stamp.string(from: request.date.addingTimeInterval(3600)))",
            "SUMMARY:\(escape(request.title))",
            "DESCRIPTION:\(escape(request.notes))",
            "END:VEVENT", "END:VCALENDAR",
        ].joined(separator: "\r\n")

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Deadline-\(request.id.uuidString.prefix(6)).ics")
        do {
            try ics.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
#endif
