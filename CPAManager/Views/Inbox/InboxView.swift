import SwiftUI
import SwiftData

/// Everything captured but not yet decided on. Swipe right to make a task, left to
/// dismiss; tap to file it under a client or project.
struct InboxView: View {
    /// True when pushed from another stack (Today's banner) so it doesn't nest a
    /// second NavigationStack.
    var embedded = false

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<InboxItem> { $0.isProcessed == false },
           sort: \InboxItem.createdAt, order: .reverse)
    private var items: [InboxItem]

    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL
    @AppStorage(SettingsKeys.reminderHour) private var reminderHour = 8
    @FocusState private var captureFocused: Bool
    @State private var quickText = ""
    @State private var triaging: InboxItem?
    @State private var toast: UndoToastState?
    @State private var showingPaste = false
    @State private var showingSetup = false
    @State private var addedCount = 0

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            captureBar
            List {
                ForEach(items) { item in
                    InboxRowCard(item: item)
                        .contentShape(Rectangle())
                        .onTapGesture { triaging = item }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button { makeTask(item) } label: { Label("Task", systemImage: "checkmark.circle") }
                                .tint(Theme.good)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button { dismiss(item) } label: { Label("Dismiss", systemImage: "xmark") }
                                .tint(Theme.neutral)
                        }
                        .contextMenu {
                            if let url = URL(string: item.link), !item.link.isEmpty {
                                Button { openURL(url) } label: { Label("Open original", systemImage: "arrow.up.right.square") }
                            }
                            Button { makeTask(item) } label: { Label("Make task", systemImage: "checkmark.circle") }
                            Button { dismiss(item) } label: { Label("Dismiss", systemImage: "xmark") }
                        }
                        .accessibilityAddTraits(.isButton)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .overlay {
                if items.isEmpty { emptyState }
            }
        }
        .background(Color.appGroupedBackground)
        .navigationTitle("Inbox")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showingPaste = true } label: {
                        Label("Paste from a note or email…", systemImage: "doc.on.clipboard")
                    }
                    Button { showingSetup = true } label: {
                        Label("Set up text & email capture", systemImage: "bolt.horizontal.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Inbox options")
            }
        }
        .sheet(isPresented: $showingPaste) { PasteCaptureSheet() }
        .sheet(isPresented: $showingSetup) { CaptureSetupView() }
        .sheet(item: $triaging) { item in
            InboxTriageSheet(item: item) { message, undo in
                toast = UndoToastState(message: message, undo: undo)
            }
            .presentationDetents([.medium, .large])
        }
        .undoToast($toast)
        .sensoryFeedback(.success, trigger: addedCount)
        .onAppear(perform: consumeFocusRequest)
        .onChange(of: router.pendingFocus) { _, _ in consumeFocusRequest() }
    }

    private func consumeFocusRequest() {
        guard router.pendingFocus == .inboxCapture else { return }
        router.pendingFocus = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            captureFocused = true
        }
    }

    private var captureBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.title3)
                .foregroundStyle(Theme.info)
                .accessibilityHidden(true)
            TextField("Capture a thought — sort it later", text: $quickText)
                .focused($captureFocused)
                .submitLabel(.done)
                .onSubmit(capture)
                .accessibilityLabel("Capture to inbox")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal).padding(.vertical, 8)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Inbox zero", systemImage: "tray")
        } description: {
            Text("Texts, emails, and notes you capture land here to be sorted into tasks.")
        } actions: {
            Button("Set up text & email capture") { showingSetup = true }
                .buttonStyle(.borderedProminent)
            Button("Paste from a note") { showingPaste = true }
        }
    }

    // MARK: Actions

    private func capture() {
        let text = quickText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        InboxService.capture(text: text, source: .manual, context: context, splitLines: false)
        quickText = ""
        addedCount += 1
    }

    private func makeTask(_ item: InboxItem) {
        let task = InboxService.makeTask(from: item, dueDate: nil, client: nil, context: context)
        NotificationScheduler.rescheduleAll(context: context, morningHour: reminderHour)
        toast = UndoToastState(message: "Task added: \(task.title)") {
            context.delete(task)
            item.reopen()
            try? context.save()
        }
    }

    private func dismiss(_ item: InboxItem) {
        item.markProcessed()
        try? context.save()
        toast = UndoToastState(message: "Dismissed", systemImage: "xmark.circle.fill") {
            item.reopen()
            try? context.save()
        }
    }
}

struct InboxRowCard: View {
    let item: InboxItem
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))

        layout {
            Image(systemName: item.source.systemImage)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.info)
                .frame(width: 44, height: 44)
                .background(Theme.info.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                    .font(.body.weight(.semibold))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(item.source.label)
                    Text("•")
                    Text(item.createdAt, style: .relative)
                    if let client = item.client {
                        Text("•")
                        Text(client.displayName).lineLimit(1)
                    }
                    if !item.attachmentName.isEmpty {
                        Image(systemName: "paperclip").accessibilityLabel("Has attachment")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.text)
        .accessibilityValue("\(item.source.label), captured \(Format.relativeDay(item.createdAt))")
        .accessibilityHint("Tap to sort. Swipe for quick actions.")
    }
}
