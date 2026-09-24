import NowCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    private static let horizons: [TimeInterval] = [4, 8, 12, 24, 48, 72].map { $0 * 3600 }
    private static let leads: [TimeInterval] = [15 * 60, 30 * 60, 3600, 2 * 3600, 24 * 3600]

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Picker("Order By", selection: $settings.ranking.mode) {
                    ForEach(RankingMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Urgent Within", selection: $settings.ranking.urgencyHorizon) {
                    ForEach(Self.horizons, id: \.self) { Text(DueLabel.duration($0)).tag($0) }
                }
            } header: {
                Text("Ranking")
            } footer: {
                Text("\(settings.ranking.mode.summary) Overdue tasks always stay on top.")
            }

            Section {
                Toggle("Use Working Hours", isOn: $settings.ranking.workingHours.isEnabled)
                if settings.ranking.workingHours.isEnabled {
                    DatePicker("Start", selection: minuteBinding($settings.ranking.workingHours.startMinute), displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: minuteBinding($settings.ranking.workingHours.endMinute), displayedComponents: .hourAndMinute)
                    WeekdayPicker(weekdays: $settings.ranking.workingHours.weekdays)
                }
            } header: {
                Text("Working Hours")
            } footer: {
                Text("When on, time left only counts working hours, and tasks with a date but no time are due at the end of the workday.")
            }

            Section("Notifications") {
                Toggle("Notify on This Device", isOn: $settings.notifyOnThisDevice)
                Picker("Heads-Up", selection: $settings.notifications.headsUpLead) {
                    ForEach(Self.leads, id: \.self) { Text("\(DueLabel.duration($0)) before").tag($0) }
                }
                if settings.ranking.workingHours.isEnabled {
                    Toggle("Hold Alerts Until Working Hours", isOn: $settings.notifications.muteOutsideWorkingHours)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }

    /// Bridges minutes-after-midnight to a DatePicker.
    private func minuteBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding {
            Calendar.current.date(byAdding: .minute, value: minutes.wrappedValue, to: Calendar.current.startOfDay(for: .now)) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }
}

private struct WeekdayPicker: View {
    @Binding var weekdays: Set<Int>

    var body: some View {
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols
        // Start from the locale's first weekday.
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }

        HStack {
            ForEach(order, id: \.self) { day in
                let on = weekdays.contains(day)
                Button {
                    if on { weekdays.remove(day) } else { weekdays.insert(day) }
                } label: {
                    Text(symbols[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .background(on ? Color.accentColor : Color.secondary.opacity(0.15), in: Circle())
                        .foregroundStyle(on ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }
}
