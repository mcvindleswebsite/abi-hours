import Foundation

struct Lunch: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var start: Date
    var end: Date?
}

struct Shift: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var start: Date
    var end: Date?
    var lunches: [Lunch] = []
    /// Set when a shift was left open too long (forgot to tap out). Fix it in the app.
    var missingClockOut: Bool = false
    /// Picked by hand in the app, or set when the shift was started from the schedule.
    /// When nil, the shift goes with that day's event automatically.
    var eventID: UUID?
    /// Started on its own at the scheduled start time from ABI (no tap).
    var autoStarted: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, start, end, lunches, missingClockOut, eventID, autoStarted
    }

    var openLunch: Lunch? { lunches.last(where: { $0.end == nil }) }

    func lunchSeconds(now: Date = Date()) -> TimeInterval {
        let shiftEnd = end ?? now
        return lunches.reduce(0) { total, lunch in
            let s = max(lunch.start, start)
            let e = min(lunch.end ?? now, shiftEnd)
            return total + max(0, e.timeIntervalSince(s))
        }
    }

    func workedSeconds(now: Date = Date()) -> TimeInterval {
        let e = end ?? now
        return max(0, e.timeIntervalSince(start) - lunchSeconds(now: now))
    }

    static func newManual(now: Date = Date()) -> Shift {
        Shift(start: now.addingTimeInterval(-4 * 3600), end: now)
    }
}

extension Shift {
    // Tolerant decoding so older saved data still loads after updates.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decodeIfPresent(Date.self, forKey: .end)
        lunches = try c.decodeIfPresent([Lunch].self, forKey: .lunches) ?? []
        missingClockOut = try c.decodeIfPresent(Bool.self, forKey: .missingClockOut) ?? false
        eventID = try c.decodeIfPresent(UUID.self, forKey: .eventID)
        autoStarted = try c.decodeIfPresent(Bool.self, forKey: .autoStarted) ?? false
    }
}

/// One event from your schedule, e.g. "Martin Lawrence" on Fri 11/20.
struct WorkEvent: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// Start of the event's day.
    var day: Date
    var name: String
    /// Scheduled start of your shift (from ABI). You're clocked in automatically at this time.
    var callTime: Date?
    /// When it was added. Only events added before their start time get a shift on their own.
    var addedAt: Date?
    /// "Not working this one" (called off, or you deleted its automatic shift).
    var skipped: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, day, name, callTime, addedAt, skipped
    }

    var sortDate: Date { callTime ?? day }
}

extension WorkEvent {
    // Tolerant decoding so events saved by older versions still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        day = try c.decode(Date.self, forKey: .day)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Shift"
        callTime = try c.decodeIfPresent(Date.self, forKey: .callTime)
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt)
        skipped = try c.decodeIfPresent(Bool.self, forKey: .skipped) ?? false
    }
}
