#if os(macOS)
import AppKit
import Carbon.HIToolbox
import SwiftData
import SwiftUI

/// The system-wide shortcut that opens the quick add bar, picked in Settings.
enum QuickAddShortcut: String, CaseIterable {
    case off, controlOptionSpace, controlOptionN, optionCommandN

    var label: String {
        switch self {
        case .off: "Off"
        case .controlOptionSpace: "⌃⌥Space"
        case .controlOptionN: "⌃⌥N"
        case .optionCommandN: "⌥⌘N"
        }
    }

    fileprivate var keyCode: Int? {
        switch self {
        case .off: nil
        case .controlOptionSpace: kVK_Space
        case .controlOptionN, .optionCommandN: kVK_ANSI_N
        }
    }

    fileprivate var modifiers: Int {
        switch self {
        case .off: 0
        case .controlOptionSpace, .controlOptionN: controlKey | optionKey
        case .optionCommandN: optionKey | cmdKey
        }
    }
}

/// Owns the global hot key and the floating quick add bar.
/// Carbon hot keys work in the sandbox and don't need Accessibility permission.
@MainActor
final class QuickAddController {
    static let shared = QuickAddController()

    private var container: ModelContainer?
    private var hotKey: EventHotKeyRef?
    private var handlerInstalled = false
    private var panel: QuickAddPanel?

    func start(container: ModelContainer, shortcut: QuickAddShortcut) {
        self.container = container
        register(shortcut)
    }

    func register(_ shortcut: QuickAddShortcut) {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        guard let keyCode = shortcut.keyCode else { return }
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x5044_4D51), id: 1) // "PDMQ"
        RegisterEventHotKey(UInt32(keyCode), UInt32(shortcut.modifiers), id, GetApplicationEventTarget(), 0, &ref)
        hotKey = ref
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { QuickAddController.shared.toggle() } }
            return noErr
        }, 1, &spec, nil, nil)
        handlerInstalled = true
    }

    func toggle() {
        if panel?.isVisible == true { close() } else { show() }
    }

    private func show() {
        guard let container else { return }
        let panel = self.panel ?? QuickAddPanel()
        self.panel = panel
        // A fresh view each time, so the field starts empty and focused.
        panel.contentView = NSHostingView(rootView: QuickAddView { [weak self] in self?.close() }.modelContainer(container))
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + frame.height * 0.68))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    private func close() {
        panel?.orderOut(nil)
    }
}

/// A borderless floating panel that takes typing without activating the whole app.
private final class QuickAddPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 580, height: 84),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView], backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }

    /// Clicking anywhere else dismisses it, like Spotlight.
    override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }
}

private struct QuickAddView: View {
    let onClose: () -> Void
    @Environment(\.modelContext) private var context
    @State private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "flag.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            TextField("Add to Podium", text: $title)
                .textFieldStyle(.plain)
                .font(.title2)
                .focused($focused)
                .onSubmit(add)
            Text("↩").foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .glassEffect(.regular, in: .capsule)
        .padding(10)
        .onAppear { focused = true }
        .onExitCommand(perform: onClose)
    }

    private func add() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return onClose() }
        context.insert(TaskItem(title: trimmed))
        try? context.save()
        onClose()
    }
}
#endif
