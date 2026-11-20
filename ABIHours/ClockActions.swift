import Foundation

/// What the badge sticker, the Action button and the in-app buttons actually do.
/// Each returns the short line shown as confirmation.
enum ClockActions {
    static let staleAfter: TimeInterval = 16 * 3600
    private static let shiftDebounce: TimeInterval = 10
    private static let lunchDebounce: TimeInterval = 4
    private static let lastShiftKey = "lastShiftToggle"
    private static let lastLunchKey = "lastLunchToggle"

    @discardableResult
    static func toggleShift(now: Date = Date()) -> String {
        let store = ShiftStore.shared
        store.closeStaleShifts(now: now)

        // A second tap within 10 seconds is a bump, not a clock-out.
        if tooSoon(lastShiftKey, now: now, window: shiftDebounce) {
            if let open = store.openShift { return "Still clocked in since \(Fmt.time(open.start))" }
            return "Still clocked out"
        }
        mark(lastShiftKey, now)

        if var shift = store.openShift {
            var endedLunch = false
            if let i = shift.lunches.lastIndex(where: { $0.end == nil }) {
                shift.lunches[i].end = now
                endedLunch = true
            }
            shift.end = now
            store.addOrUpdate(shift)
            Notifier.cancelLunch()
            let worked = Fmt.duration(shift.workedSeconds(now: now))
            let lunchNote = endedLunch ? " (lunch ended)" : ""
            if let name = store.event(for: shift)?.name {
                return "Clocked out of \(name) · \(worked)\(lunchNote)"
            }
            return "Clocked out at \(Fmt.time(now)) · \(worked)\(lunchNote)"
        } else {
            let shift = Shift(start: now)
            store.addOrUpdate(shift)
            if let name = store.event(for: shift)?.name {
                return "Clocked in for \(name) · \(Fmt.time(now))"
            }
            return "Clocked in at \(Fmt.time(now))"
        }
    }

    @discardableResult
    static func toggleLunch(now: Date = Date()) -> String {
        let store = ShiftStore.shared
        store.closeStaleShifts(now: now)
        guard var shift = store.openShift else {
            return "You're not clocked in. Tap your badge first."
        }
        if tooSoon(lastLunchKey, now: now, window: lunchDebounce) {
            return shift.openLunch != nil ? "Still on lunch" : "Lunch already ended"
        }
        mark(lastLunchKey, now)

        if let i = shift.lunches.lastIndex(where: { $0.end == nil }) {
            shift.lunches[i].end = now
            let length = now.timeIntervalSince(shift.lunches[i].start)
            store.addOrUpdate(shift)
            Notifier.cancelLunch()
            return "Lunch over · \(Fmt.duration(length))"
        } else {
            shift.lunches.append(Lunch(start: now))
            store.addOrUpdate(shift)
            let minutes = AppSettings.lunchMinutes
            Notifier.scheduleLunch(start: now, lengthMinutes: minutes, headsUpMinutes: AppSettings.headsUpMinutes)
            let backBy = now.addingTimeInterval(TimeInterval(minutes * 60))
            return "Lunch started · back by \(Fmt.time(backBy))"
        }
    }

    /// Used by the "End lunch" button on the reminder. Never starts a lunch.
    @discardableResult
    static func endLunch(now: Date = Date()) -> String {
        let store = ShiftStore.shared
        guard var shift = store.openShift,
              let i = shift.lunches.lastIndex(where: { $0.end == nil }) else {
            Notifier.cancelLunch()
            return "Not on lunch"
        }
        shift.lunches[i].end = now
        let length = now.timeIntervalSince(shift.lunches[i].start)
        store.addOrUpdate(shift)
        Notifier.cancelLunch()
        mark(lastLunchKey, now)
        return "Lunch over · \(Fmt.duration(length))"
    }

    private static func tooSoon(_ key: String, now: Date, window: TimeInterval) -> Bool {
        let last = UserDefaults.standard.double(forKey: key)
        guard last > 0 else { return false }
        let gap = now.timeIntervalSinceReferenceDate - last
        return gap >= 0 && gap < window
    }

    private static func mark(_ key: String, _ now: Date) {
        UserDefaults.standard.set(now.timeIntervalSinceReferenceDate, forKey: key)
    }
}
