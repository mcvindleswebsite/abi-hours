import Foundation

enum Fmt {
    static func time(_ d: Date) -> String {
        d.formatted(date: .omitted, time: .shortened)
    }

    /// "Thu, Nov 20"
    static func day(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "Thu, 11/20"
    static func shortDay(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.abbreviated).month(.defaultDigits).day())
    }

    /// "4:30 PM" today, "tomorrow 12:30 PM", otherwise "Sat 12:30 PM".
    static func when(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return time(d) }
        if cal.isDateInTomorrow(d) { return "tomorrow \(time(d))" }
        return "\(d.formatted(.dateTime.weekday(.abbreviated))) \(time(d))"
    }

    /// "6h 12m"
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds / 60))
        let h = total / 60
        let m = total % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// "18.50 hrs"
    static func hours(_ seconds: TimeInterval) -> String {
        String(format: "%.2f hrs", max(0, seconds) / 3600)
    }
}

enum AppSettings {
    static let lunchKey = "lunchMinutes"
    static let headsUpKey = "headsUpMinutes"

    static var lunchMinutes: Int {
        let v = UserDefaults.standard.integer(forKey: lunchKey)
        return v > 0 ? v : 30
    }

    /// Minutes before lunch ends to send the heads-up. 0 turns it off.
    static var headsUpMinutes: Int {
        UserDefaults.standard.object(forKey: headsUpKey) as? Int ?? 5
    }
}

struct Week: Hashable {
    let start: Date
    let end: Date // exclusive

    /// "Nov 16 – 22" or "Nov 30 – Dec 6"
    var title: String {
        let cal = Calendar.current
        let last = cal.date(byAdding: .day, value: -1, to: end) ?? end
        let startText = start.formatted(.dateTime.month(.abbreviated).day())
        let sameMonth = cal.component(.month, from: start) == cal.component(.month, from: last)
        let endText = sameMonth
            ? last.formatted(.dateTime.day())
            : last.formatted(.dateTime.month(.abbreviated).day())
        return "\(startText) – \(endText)"
    }
}

enum Weeks {
    static let startDayKey = "weekStartDay"

    /// Calendar weekday the week starts on (1 = Sunday … 7 = Saturday). Defaults to Monday.
    static var firstWeekday: Int {
        let v = UserDefaults.standard.integer(forKey: startDayKey)
        return (1...7).contains(v) ? v : 2
    }

    static func week(containing date: Date) -> Week {
        var cal = Calendar.current
        cal.firstWeekday = firstWeekday
        if let interval = cal.dateInterval(of: .weekOfYear, for: date) {
            return Week(start: interval.start, end: interval.end)
        }
        let s = cal.startOfDay(for: date)
        return Week(start: s, end: cal.date(byAdding: .day, value: 7, to: s) ?? s)
    }
}
