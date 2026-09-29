#if os(iOS)
import ActivityKit
import Foundation

/// A running task timer, shown as a Live Activity on the lock screen and in the Dynamic Island.
/// Everything is fixed when the timer starts, so there's no changing state.
struct TaskTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {}

    let taskID: UUID
    let title: String
    let start: Date
    let end: Date
}
#endif
