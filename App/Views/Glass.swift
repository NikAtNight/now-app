import SwiftUI

/// What sits behind lists and forms: neutral, like Apple's own apps. On Mac nothing, since the
/// window uses the popover material (see `PopoverMaterial`); on iPhone the grouped background.
struct ListBackdrop: View {
    var body: some View {
        #if os(macOS)
        Color.clear
        #else
        Color(.systemGroupedBackground).ignoresSafeArea()
        #endif
    }
}

#if os(macOS)
/// The popover's own material behind the whole window, pinned to its active look. A standard
/// window material dims when the window stops being key, which happens as a popover opens and made
/// the list flicker.
struct PopoverMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
#endif

/// A sheet in the app's glass style. Mac sheets draw toolbars as opaque bars, so there the title and
/// Done button sit inside the glass. iOS keeps the standard (already glass) navigation bar.
/// The content should hide its own scroll background.
struct GlassSheet<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.title3.bold())
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.glassProminent)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            content
        }
        .background { ListBackdrop() }
        .presentationBackground(.thinMaterial)
        // A fixed width, narrow enough to sit inside the list window at its narrowest rather than hang
        // past its edges. A minimum or ideal width loses to the list's own preferred width.
        .frame(width: 340)
        .frame(minHeight: 560)
        #else
        NavigationStack {
            content
                .background { ListBackdrop() }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #endif
    }
}

extension View {
    /// Shows a list row as a rounded card, like a grouped form row. The row being edited gets an accent tint.
    func cardRow(highlighted: Bool = false) -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(highlighted ? AnyShapeStyle(Color.accentColor.opacity(0.14)) : cardFill, in: .rect(cornerRadius: 12))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(.cardRow)
    }
}

/// Matches the popover's form rows on Mac and grouped cells on iPhone.
private var cardFill: AnyShapeStyle {
    #if os(macOS)
    AnyShapeStyle(Color.primary.opacity(0.06))
    #else
    AnyShapeStyle(Color(.secondarySystemGroupedBackground))
    #endif
}

extension EdgeInsets {
    /// Card spacing. The Mac list already pads its rows, so cards line up with the title there.
    static var cardRow: EdgeInsets {
        #if os(macOS)
        EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0)
        #else
        EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12)
        #endif
    }
}

#if os(macOS)
import AppKit

/// SwiftUI's field editor paints an opaque text background while you edit, which covers the glass rows.
extension NSTextView {
    override open var drawsBackground: Bool {
        get { false }
        set {}
    }
}

/// SwiftUI leaves spelling correction off in its text fields. As each text view gets focus, this
/// turns on autocorrect, text replacement, and spell checking per the system's Keyboard > Text Input
/// settings, like other Mac apps.
@MainActor
enum TextInputSettings {
    static func install() {
        NotificationCenter.default.addObserver(forName: NSTextView.didChangeSelectionNotification, object: nil, queue: .main) { note in
            guard let view = note.object as? NSTextView else { return }
            MainActor.assumeIsolated { apply(to: view) }
        }
    }

    private static func apply(to view: NSTextView) {
        guard view.isEditable else { return }
        let correct = NSSpellChecker.isAutomaticSpellingCorrectionEnabled
        let replace = NSSpellChecker.isAutomaticTextReplacementEnabled
        if view.isAutomaticSpellingCorrectionEnabled != correct { view.isAutomaticSpellingCorrectionEnabled = correct }
        if view.isAutomaticTextReplacementEnabled != replace { view.isAutomaticTextReplacementEnabled = replace }
        if !view.isContinuousSpellCheckingEnabled { view.isContinuousSpellCheckingEnabled = true }
    }
}
#endif
