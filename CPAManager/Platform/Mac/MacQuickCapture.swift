#if os(macOS)
import SwiftUI
import SwiftData
import AppKit
import Carbon.HIToolbox

/// The capture field shared by the menu bar popover and the global-hotkey panel:
/// type a line, press Return, and it lands as a task (dates and "every week" parsed)
/// or in the Inbox to sort later.
struct QuickCaptureView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case task, inbox
        var id: String { rawValue }
        var label: String { self == .task ? "Task" : "Inbox" }
        var prompt: String {
            self == .task ? "Add a task — “call Smith Friday”" : "Capture a thought — sort it later"
        }
    }

    /// Called shortly after a successful capture (the hotkey panel closes itself).
    var onFinished: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKeys.reminderHour) private var reminderHour = 8
    @AppStorage("quickCaptureMode") private var modeRaw = Mode.task.rawValue
    @State private var text = ""
    @State private var confirmation: String?
    @FocusState private var focused: Bool

    private var mode: Binding<Mode> {
        Binding(get: { Mode(rawValue: modeRaw) ?? .task }, set: { modeRaw = $0.rawValue })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Capture as", selection: mode) {
                ForEach(Mode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField(mode.wrappedValue.prompt, text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(submit)

            HStack {
                if let confirmation {
                    Label(confirmation, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.good)
                } else {
                    Text("⌃⌥Space opens this anywhere")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open CPA Manager") { Self.openMainWindow() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .padding(14)
        .frame(width: 380)
        .onAppear { focused = true }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch mode.wrappedValue {
        case .task:
            let parsed = QuickCapture.parse(trimmed)
            guard !parsed.title.isEmpty else { return }
            let task = TaskItem(title: parsed.title, dueDate: parsed.dueDate, isNextAction: parsed.dueDate == nil)
            task.repeatRule = parsed.rule
            context.insert(task)
            try? context.save()
            NotificationScheduler.rescheduleAll(context: context, morningHour: reminderHour)
            confirmation = parsed.dueDate.map { "Added — due \(Format.relativeDay($0).lowercased())" } ?? "Added to Next up"
        case .inbox:
            InboxService.capture(text: trimmed, source: .manual, context: context, splitLines: false)
            confirmation = "Added to Inbox"
        }
        SnapshotBuilder.rebuild(context: context)
        text = ""

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            confirmation = nil
            onFinished?()
        }
    }

    static func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
}

/// A floating capture panel summoned by the global hotkey (⌃⌥Space).
@MainActor
final class CapturePanelController {
    static let shared = CapturePanelController()

    private final class FloatingPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private var panel: NSPanel?
    private var resignObserver: NSObjectProtocol?

    func toggle() {
        if let panel, panel.isVisible { close() } else { show() }
    }

    func show() {
        close()
        let root = QuickCaptureView(onFinished: { [weak self] in self?.close() })
            .modelContainer(Persistence.shared.container)
        let host = NSHostingController(rootView: root)

        let panel = FloatingPanel(contentViewController: host)
        panel.styleMask = [.titled, .fullSizeContentView]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.center()

        // Like Spotlight: clicking away dismisses it.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }

        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        panel?.orderOut(nil)
        panel = nil
    }
}

/// System-wide hotkey via Carbon's `RegisterEventHotKey` — works in the sandbox and
/// needs no Accessibility permission.
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    fileprivate var action: (() -> Void)?

    func register(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        unregister()
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { hotKey.action?() }
                return noErr
            },
            1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )

        let id = EventHotKeyID(signature: OSType(0x43504148), id: 1)   // 'CPAH'
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }
}

enum MacQuickCapture {
    /// ⌃⌥Space → floating capture panel.
    @MainActor
    static func installHotKey() {
        GlobalHotKey.shared.register(keyCode: kVK_Space, modifiers: controlKey | optionKey) {
            CapturePanelController.shared.toggle()
        }
    }
}
#endif
