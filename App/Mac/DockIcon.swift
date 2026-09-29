#if os(macOS)
import AppKit
import SwiftUI

/// Where the Dock icon shows, picked in Settings. Podium always lives in the menu bar (unless that's
/// turned off too), so by default it only takes a Dock and ⌘Tab spot while a window is open.
enum DockIconMode: String, CaseIterable {
    case whileWindowOpen, always, never

    var label: String {
        switch self {
        case .whileWindowOpen: "While Window Is Open"
        case .always: "Always"
        case .never: "Never"
        }
    }
}

/// Switches the app between a regular app (Dock and ⌘Tab) and a menu bar accessory as windows open
/// and close.
@MainActor
final class DockIconController {
    static let shared = DockIconController()

    private var mode = DockIconMode.whileWindowOpen
    private var observers: [NSObjectProtocol] = []

    func start(mode: DockIconMode) {
        self.mode = mode
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification, NSWindow.didChangeOcclusionStateNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                // After a close, the window is still visible until this turn of the run loop ends.
                DispatchQueue.main.async { MainActor.assumeIsolated { DockIconController.shared.update() } }
            })
        }
        update()
    }

    func setMode(_ mode: DockIconMode) {
        self.mode = mode
        update()
    }

    private func update() {
        let wanted: NSApplication.ActivationPolicy = switch mode {
        case .always: .regular
        case .never: .accessory
        case .whileWindowOpen: hasOpenWindow ? .regular : .accessory
        }
        guard NSApp.activationPolicy() != wanted else { return }
        NSApp.setActivationPolicy(wanted)
        // Becoming a regular app can drop focus; keep the window that's opening in front.
        if wanted == .regular { NSApp.activate() }
    }

    /// A real window: the main window or Settings. Not the menu bar panel or the quick add bar.
    private var hasOpenWindow: Bool {
        NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel) }
    }
}
/// Opens the Settings window and brings it to the front. Needed as a button because without a Dock
/// icon Podium has no menu bar, and an accessory app's windows otherwise open behind other apps.
struct OpenSettingsButton<Label: View>: View {
    @ViewBuilder var label: Label
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button {
            openSettings()
            NSApp.activate()
            // macOS can decline to activate a menu bar app, so raise the window itself as well.
            DispatchQueue.main.async {
                NSApp.windows.first { $0.identifier?.rawValue.contains("Settings") == true }?.orderFrontRegardless()
            }
        } label: {
            label
        }
    }
}
#endif
