import SwiftUI
import ContactsUI
import Contacts

/// Wraps `CNContactPickerViewController`. The system contact picker runs out
/// of process and needs no Contacts permission (same model as PhotosPicker).
/// `onComplete` fires with the picked contact, or `nil` if the user cancels —
/// the caller is expected to flip its own `isPresented` binding to `false`.
struct ContactPickerView: UIViewControllerRepresentable {
    var onComplete: (CNContact?) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onComplete: (CNContact?) -> Void
        init(onComplete: @escaping (CNContact?) -> Void) { self.onComplete = onComplete }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onComplete(contact)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onComplete(nil)
        }
    }
}
