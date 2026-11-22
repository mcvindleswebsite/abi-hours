import Foundation

/// One event (or one day with no event) and the shifts you worked for it.
struct EventGroup: Identifiable {
    let id: String
    let day: Date
    let event: WorkEvent?
    var shifts: [Shift]

    var title: String { event?.name ?? "Shift" }
    var sortDate: Date { event?.callTime ?? shifts.map(\.start).min() ?? day }

    func worked(now: Date) -> TimeInterval {
        shifts.reduce(0) { $0 + $1.workedSeconds(now: now) }
    }
}

struct WeekGroup: Identifiable {
    let week: Week
    var items: [EventGroup]
    var id: Date { week.start }

    func worked(now: Date) -> TimeInterval {
        items.reduce(0) { $0 + $1.worked(now: now) }
    }
}

/// Everything is saved as JSON in the app's own folder, on this phone only.
/// App Intents (badge sticker, Action button) run inside the app's process, so they share this store.
final class ShiftStore: ObservableObject {
    static let shared = ShiftStore()

    @Published private(set) var shifts: [Shift] = []   // oldest first
    @Published private(set) var events: [WorkEvent] = []

    private let shiftsURL: URL
    private let eventsURL: URL

    init() {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        shiftsURL = dir.appendingPathComponent("shifts.json")
        eventsURL = dir.appendingPathComponent("events.json")
        shifts = (Self.read([Shift].self, from: shiftsURL) ?? []).sorted { $0.start < $1.start }
        events = (Self.read([WorkEvent].self, from: eventsURL) ?? []).sorted { $0.sortDate < $1.sortDate }
    }

    // MARK: Shifts

    var openShift: Shift? { shifts.last(where: { $0.end == nil }) }

    func addOrUpdate(_ shift: Shift) {
        if let i = shifts.firstIndex(where: { $0.id == shift.id }) {
            shifts[i] = shift
        } else {
            shifts.append(shift)
        }
        shifts.sort { $0.start < $1.start }
        saveShifts()
    }

    func deleteShift(id: UUID) {
        // Deleting a shift that started on its own means you didn't work that event,
        // so don't start it again.
        if let s = shifts.first(where: { $0.id == id }), s.autoStarted, let eventID = s.eventID,
           let i = events.firstIndex(where: { $0.id == eventID }) {
            events[i].skipped = true
            saveEvents()
        }
        shifts.removeAll { $0.id == id }
        saveShifts()
    }

    /// Run before anything reads the current state: flags forgotten clock-outs, then starts scheduled shifts.
    func refresh(now: Date = Date()) {
        closeStaleShifts(now: now)
        startScheduledShifts(now: now)
    }

    /// You're clocked in at the scheduled start from ABI without tapping anything.
    /// The shift is created the next time the app or the sticker/Action button runs,
    /// with its start set to the scheduled time, so it doesn't matter when that is.
    func startScheduledShifts(now: Date = Date()) {
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let due = events
            .filter { e in
                guard let start = e.callTime else { return false }
                return !e.skipped && start <= now && start >= weekAgo
            }
            .sorted { $0.sortDate < $1.sortDate }

        var changed = false
        for e in due {
            guard let start = e.callTime else { continue }
            if hasShift(e, start: start, now: now) { continue }

            if now.timeIntervalSince(start) <= ClockActions.staleAfter {
                // Normal case: start the shift. Skip events loaded after they'd already started.
                guard (e.addedAt ?? .distantPast) < start, openShift == nil else { continue }
                shifts.append(Shift(start: start, eventID: e.id, autoStarted: true))
            } else {
                // Long past and never clocked out: keep a record and flag it so you can fill in the time.
                guard let added = e.addedAt, added < start else { continue }
                shifts.append(Shift(start: start, end: start, missingClockOut: true, eventID: e.id, autoStarted: true))
            }
            changed = true
        }
        if changed {
            shifts.sort { $0.start < $1.start }
            saveShifts()
        }
    }

    /// True if the event already has a shift (tapped in, added by hand, started earlier),
    /// or a shift was already running at its start (two events back to back).
    private func hasShift(_ e: WorkEvent, start: Date, now: Date) -> Bool {
        shifts.contains(where: { event(for: $0)?.id == e.id })
            || shifts.contains(where: { $0.start <= start && ($0.end ?? now) >= start })
    }

    /// An event that has already started (within the last 16 hours) but has no shift,
    /// e.g. the schedule was loaded after it started.
    func startedEventWithoutShift(now: Date) -> WorkEvent? {
        events
            .filter { e in
                guard let start = e.callTime, !e.skipped, start <= now,
                      now.timeIntervalSince(start) <= ClockActions.staleAfter else { return false }
                return !hasShift(e, start: start, now: now)
            }
            .max { $0.sortDate < $1.sortDate }
    }

    /// Next scheduled start within `window`, e.g. to answer an early sticker tap.
    func upcomingEvent(after now: Date, within window: TimeInterval) -> WorkEvent? {
        events
            .filter { e in
                guard let start = e.callTime else { return false }
                return !e.skipped && start > now && start <= now.addingTimeInterval(window)
            }
            .min { $0.sortDate < $1.sortDate }
    }

    /// A shift still open after 16 hours means you forgot to tap out. It gets flagged so you can fix it,
    /// and your next tap starts a new shift instead of ending a 20-hour one.
    func closeStaleShifts(now: Date = Date()) {
        var changed = false
        for i in shifts.indices where shifts[i].end == nil && now.timeIntervalSince(shifts[i].start) > ClockActions.staleAfter {
            shifts[i].end = shifts[i].start
            shifts[i].missingClockOut = true
            for j in shifts[i].lunches.indices where shifts[i].lunches[j].end == nil {
                shifts[i].lunches[j].end = shifts[i].lunches[j].start
            }
            changed = true
        }
        if changed {
            saveShifts()
            Notifier.cancelLunch()
        }
    }

    // MARK: Events

    func eventsOnDay(_ date: Date) -> [WorkEvent] {
        let cal = Calendar.current
        return events.filter { cal.isDate($0.day, inSameDayAs: date) }
    }

    /// The event on the same day as `date`. With two events that day, the one whose call time is closest.
    func autoEvent(for date: Date) -> WorkEvent? {
        let candidates = eventsOnDay(date)
        if candidates.count <= 1 { return candidates.first }
        return candidates.min { a, b in
            abs((a.callTime ?? a.day).timeIntervalSince(date)) < abs((b.callTime ?? b.day).timeIntervalSince(date))
        }
    }

    func event(for shift: Shift) -> WorkEvent? {
        if let id = shift.eventID, let picked = events.first(where: { $0.id == id }) {
            return picked
        }
        return autoEvent(for: shift.start)
    }

    /// The next event (today or later) you haven't worked yet.
    func nextEvent(from now: Date) -> WorkEvent? {
        let today = Calendar.current.startOfDay(for: now)
        let worked = Set(shifts.compactMap { event(for: $0)?.id })
        return events
            .filter { $0.day >= today && !$0.skipped && !worked.contains($0.id) }
            .min { $0.sortDate < $1.sortDate }
    }

    /// Adds pasted events. Any day in the paste replaces what was saved for that day,
    /// so pasting an updated schedule fixes changes instead of making duplicates.
    func importEvents(_ incoming: [WorkEvent]) {
        let cal = Calendar.current
        let days = Set(incoming.map { cal.startOfDay(for: $0.day) })
        let replaced = events.filter { days.contains(cal.startOfDay(for: $0.day)) }
        var result = events.filter { !days.contains(cal.startOfDay(for: $0.day)) }
        let now = Date()
        for var e in incoming {
            e.day = cal.startOfDay(for: e.day)
            // Keep the same ID for the same event so shifts linked to it stay linked.
            if let old = replaced.first(where: {
                cal.isDate($0.day, inSameDayAs: e.day) && $0.name.caseInsensitiveCompare(e.name) == .orderedSame
            }) {
                e.id = old.id
                e.addedAt = old.addedAt ?? now
                e.skipped = old.skipped
            } else {
                e.addedAt = now
            }
            result.append(e)
        }
        events = result.sorted { $0.sortDate < $1.sortDate }
        saveEvents()
    }

    func addOrUpdateEvent(_ event: WorkEvent) {
        var e = event
        if let i = events.firstIndex(where: { $0.id == e.id }) {
            if e.addedAt == nil { e.addedAt = events[i].addedAt ?? Date() }
            events[i] = e
        } else {
            if e.addedAt == nil { e.addedAt = Date() }
            events.append(e)
        }
        events.sort { $0.sortDate < $1.sortDate }
        saveEvents()
    }

    func deleteEvent(id: UUID) {
        events.removeAll { $0.id == id }
        saveEvents()
    }

    // MARK: Grouping for the main screen

    /// Weeks → events → shifts. Shifts on a day with no event show up as "Shift" for that day.
    func weekGroups(now: Date) -> [WeekGroup] {
        let cal = Calendar.current
        var byEvent: [UUID: EventGroup] = [:]
        for e in events {
            byEvent[e.id] = EventGroup(id: e.id.uuidString, day: e.day, event: e, shifts: [])
        }
        var loose: [Date: EventGroup] = [:]
        for s in shifts {
            if let e = event(for: s), byEvent[e.id] != nil {
                byEvent[e.id]?.shifts.append(s)
            } else {
                let day = cal.startOfDay(for: s.start)
                let id = "day-\(Int(day.timeIntervalSinceReferenceDate))"
                loose[day, default: EventGroup(id: id, day: day, event: nil, shifts: [])].shifts.append(s)
            }
        }

        var byWeek: [Date: WeekGroup] = [:]
        for item in Array(byEvent.values) + Array(loose.values) {
            let w = Weeks.week(containing: item.day)
            byWeek[w.start, default: WeekGroup(week: w, items: [])].items.append(item)
        }
        let thisWeek = Weeks.week(containing: now)
        if byWeek[thisWeek.start] == nil {
            byWeek[thisWeek.start] = WeekGroup(week: thisWeek, items: [])
        }

        return byWeek.values.map { group in
            var g = group
            g.items = g.items.map { item in
                var i = item
                i.shifts.sort { $0.start < $1.start }
                return i
            }
            g.items.sort { $0.sortDate < $1.sortDate }
            return g
        }
    }

    // MARK: Saving

    private func saveShifts() { Self.write(shifts, to: shiftsURL) }
    private func saveEvents() { Self.write(events, to: eventsURL) }

    private static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Never overwrite a file we couldn't read. Move it aside instead.
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = url.deletingPathExtension().appendingPathExtension("unreadable-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            return nil
        }
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) {
        do {
            let data = try JSONEncoder().encode(value)
            // Writable while the phone is locked (after the first unlock since restart),
            // so the Action button works from the lock screen.
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            print("ABI Hours: couldn't save \(url.lastPathComponent): \(error)")
        }
    }
}
