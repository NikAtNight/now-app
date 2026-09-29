import NowCore
import SwiftUI

/// How priorities are drawn, picked in Settings. Shared with the widget so both look the same.
enum PriorityStyle: String, CaseIterable {
    case bars, arrows, marks

    var label: String {
        switch self {
        case .bars: "Bars"
        case .arrows: "Arrows"
        case .marks: "Marks"
        }
    }

    /// Nil for marks (which are text) and for no priority. Menus use this uncolored.
    func image(for priority: Priority) -> Image? {
        switch (self, priority) {
        case (_, .none), (.marks, _): nil
        case (.bars, .low): Image(systemName: "cellularbars", variableValue: 0.25)
        case (.bars, .medium): Image(systemName: "cellularbars", variableValue: 0.5)
        case (.bars, .high): Image(systemName: "cellularbars", variableValue: 1)
        case (.arrows, .low): Image(systemName: "arrow.down")
        case (.arrows, .medium): Image(systemName: "equal")
        case (.arrows, .high): Image(systemName: "arrow.up")
        }
    }
}

extension Priority {
    var color: Color {
        switch self {
        case .none: .secondary
        case .low: .blue
        case .medium: .orange
        case .high: .red
        }
    }
}
