#if os(iOS)
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// A running task timer on the lock screen and in the Dynamic Island.
struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TaskTimerAttributes.self) { context in
            LockScreenTimer(attributes: context.attributes)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.35))
        } dynamicIsland: { context in
            let attributes = context.attributes
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(attributes.title, systemImage: "timer")
                        .lineLimit(1)
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(attributes)
                        .font(.title3.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        ProgressView(timerInterval: attributes.start...attributes.end, countsDown: false)
                            .labelsHidden()
                        Button(intent: CompleteTaskIntent(taskID: attributes.taskID)) {
                            Label("Done", systemImage: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(.tint)
            } compactTrailing: {
                countdown(attributes).frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(.tint)
            }
        }
    }
}

private func countdown(_ attributes: TaskTimerAttributes) -> some View {
    Text(timerInterval: attributes.start...max(attributes.start, attributes.end), countsDown: true)
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
}

private struct LockScreenTimer: View {
    let attributes: TaskTimerAttributes

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(attributes.title, systemImage: "timer")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                countdown(attributes)
                    .font(.title2.weight(.semibold))
            }
            HStack {
                ProgressView(timerInterval: attributes.start...attributes.end, countsDown: false)
                    .labelsHidden()
                Button(intent: CompleteTaskIntent(taskID: attributes.taskID)) {
                    Label("Done", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
#endif
