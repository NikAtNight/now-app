import NowCore
import SwiftUI

/// The priority glyph in the style picked in Settings. Draws nothing for no priority.
struct PriorityIcon: View {
    let priority: Priority
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if priority != .none {
            if let image = settings.priorityStyle.image(for: priority) {
                image.foregroundStyle(priority.color)
            } else {
                Text(priority.marks).foregroundStyle(priority.color)
            }
        }
    }
}

/// A priority menu or picker item: the style's icon next to the name.
struct PriorityLabel: View {
    let priority: Priority
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if let image = settings.priorityStyle.image(for: priority) {
            Label { Text(priority.label) } icon: { image }
        } else {
            Text(priority == .none ? priority.label : "\(priority.marks) \(priority.label)")
        }
    }
}
