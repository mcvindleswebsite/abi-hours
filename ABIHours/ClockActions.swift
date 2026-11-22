import Foundation

/// What the badge sticker, the Action button and the in-app buttons actually do.
/// Each returns the short line shown as confirmation.
///
/// Clock-in comes from your ABI schedule: at an event's scheduled start you're clocked in
/// on your own (see ShiftStore.startScheduledShifts). The sticker is for clocking out.
enum ClockActions {
    static let staleAfter: TimeInterval = 16 * 3600
    /// Tapping the sticker again within this long after clocking out undoes the clock-out.
    static let undoWindow: TimeInterval = 15 * 60
    private static let shiftDebounce: TimeInterval = 10
    private static let lunchDebounce: TimeInterval = 4
    private static let lastShiftKey = "lastShiftToggle"
    private static let lastLunchKey = "lastLunchToggle"

    /// The badge sticker.
    @discardableResult
    static func toggleShift(now: Date = Date()) -> String {
        let store = ShiftStore.shared
        store.refresh(now: now)

        // A second tap within 10 seconds is a bump.
        if tooSoon(lastShiftKey, now: now, window: shiftDebounce) {
            if let open = store.openShift { return "Still clocked in since \(Fmt.time(open.start))" }
            return "Already clocked out"
        }
        mark(lastShiftKey, now)

        // Normal case: you're on the clock (started from the schedule), so this is clocking out.
        if let open = store.openShift {
            return clockOut(open, now: now, store: store)
        }

        // Tapped again shortly after clocking out: undo it.
        let closed = store.shifts.filter { $0.end != nil && !$0.missingClockOut }
        if let last = closed.max(by: { ($0.end ?? .distantPast) < ($1.end ?? .distantPast) }),
           let end = last.end, now >= end, now.timeIntervalSince(end) < undoWindow {
            var reopened = last
            reopened.end = nil
            store.addOrUpdate(reopened)
            return "Undid clock-out · still clocked in since \(Fmt.time(reopened.start))"
        }

        // Today's event started but isn't running (e.g. the schedule was loaded late).
        if let event = store.startedEventWithoutShift(now: now), let start = event.callTime {
            if now.timeIntervalSince(start) < 3600 {
                // Tapped near the start: treat it as arriving.
                store.addOrUpdate(Shift(start: start, eventID: event.id, autoStarted: true))
                return "Clocked in for \(event.name) from \(Fmt.time(start))"
            }
            // Later in the shift: this is clocking out, from the scheduled start.
            let shift = Shift(start: start, end: now, eventID: event.id, autoStarted: true)
            store.addOrUpdate(shift)
            return "Clocked out of \(event.name) · \(Fmt.duration(shift.workedSeconds(now: now))) since \(Fmt.time(start))"
        }

        // Tapped before the shift starts: nothing to do, it starts on its own.
        if let next = store.upcomingEvent(after: now, within: 12 * 3600), let start = next.callTime {
            return "\(next.name) starts \(Fmt.when(start)). You'll be clocked in automatically."
        }

        // Nothing scheduled: clock in now, and the next tap clocks out.
        let shift = Shift(start: now)
        store.addOrUpdate(shift)
        if let name = store.event(for: shift)?.name {
            return "Clocked in for \(name) at \(Fmt.time(now))"
        }
        return "Nothing scheduled · clocked in at \(Fmt.time(now)). Tap again when you leave."
    }

    /// In-app "Clock in" button.
    @discardableResult
    static func clockInNow(now: Date = Date()) -> String {
        let store = ShiftStore.shared
        store.refresh(now: now)
        if let open = store.openShift { return "Already clocked in since \(Fmt.time(open.start))" }
        mark(lastShiftKey, now)
        if let event = store.startedEventWithoutShift(now: now), let start = event.callTime {
            store.addOrUpdate(Shift(start: start, eventID: event.id, autoStarted: true))
            return "Clocked in for \(event.name) from \(Fmt.time(start))"
        }
        store.addOrUpdate(Shift(start: now))
        return "Clocked in at \(Fmt.time(now))"
    }

    /// In-app "Clock out" button.
    @discardableResult
    static func clockOutNow(now: Date = Date()) -> String {
        let store = ShiftStore.shared
        store.refresh(now: now)
        guard let open = store.openShift else { return "Not clocked in" }
        mark(lastShiftKey, now)
        return clockOut(open, now: now, store: store)
    }

    private static func clockOut(_ open: Shift, now: Date, store: ShiftStore) -> String {
        var shift = open
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
    }

    @discardableResult
    static func toggleLunch(now: Date = Date()) -> String {
        let store = ShiftStore.shared
        store.refresh(now: now)
        guard var shift = store.openShift else {
            if let next = store.upcomingEvent(after: now, within: 12 * 3600), let start = next.callTime {
                return "Your shift starts \(Fmt.when(start))"
            }
            return "You're not clocked in"
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
