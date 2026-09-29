import Foundation

extension Calendar {
    /// The local clock time `minute` minutes after midnight on the day containing `day`.
    /// Uses clock fields, not elapsed time, so it stays right on daylight-saving days.
    func date(atMinute minute: Int, on day: Date) -> Date? {
        var components = dateComponents([.era, .year, .month, .day], from: day)
        components.hour = minute / 60
        components.minute = minute % 60
        return date(from: components)
    }
}
