import Foundation

struct ParsedEvent: Identifiable, Hashable {
    var id = UUID()
    var day: Date
    var name: String
    var callTime: Date?
}

/// Reads a plain-text schedule (like the ones Claude writes) into events.
/// Handles lines like:
///   Thu 11/20 — Martin Lawrence — call 5:00 PM
///   **Thursday, November 20** (name and "Call: 5:00 PM" on the next lines)
///   - 11/22 (Sat): Ontario Reign vs. San Diego Gulls @ 4p
/// Header lines ("Week of 11/17", "Nov 17 – Nov 23") and days off are skipped.
/// Mirrors tools/parser_reference.py, which is what the test cases run against.
enum ScheduleParser {

    static func parse(_ text: String, today: Date = Date(), calendar: Calendar = .current) -> [ParsedEvent] {
        var results: [ParsedEvent] = []
        var currentDay: Date?
        var pending: Int?   // event whose name should come from the next line
        var last: Int?      // latest event; a time on its own line attaches here

        for raw in text.components(separatedBy: .newlines) {
            let line = stripMarkdown(raw)
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }

            let hits = findDates(in: line, today: today, calendar: calendar)
            if !hits.isEmpty {
                let ns = line as NSString
                let prefix = ns.substring(to: hits[0].range.location)
                var segments: [String] = []
                for (i, hit) in hits.enumerated() {
                    let from = hit.range.location + hit.range.length
                    let to = i + 1 < hits.count ? hits[i + 1].range.location : ns.length
                    segments.append(ns.substring(with: NSRange(location: from, length: max(0, to - from))))
                }

                let prefixName = clean(prefix, leadingWeekday: true, trailingWeekday: true)
                let segmentNames = segments.enumerated().map { i, seg in
                    clean(seg, leadingWeekday: true, trailingWeekday: i < segments.count - 1)
                }
                // "Thu 11/20: Martin Lawrence, Fri 11/21: Reign" → one name per date.
                let perDate = hits.count > 1 && prefixName.isEmpty && segmentNames.allSatisfy { !$0.isEmpty }
                let shared = ([prefixName] + segmentNames).filter { !$0.isEmpty }.joined(separator: " ")
                let sharedLower = shared.lowercased()

                if !perDate {
                    if isHeader(sharedLower) || (hits.count > 1 && shared.isEmpty) || isDayOff(sharedLower) {
                        currentDay = nil; pending = nil; last = nil
                        continue
                    }
                }

                for (i, hit) in hits.enumerated() {
                    let name = perDate ? segmentNames[i] : shared
                    let timeSource = perDate ? segments[i] : prefix + " " + segments.joined(separator: " ")
                    let time = firstTime(in: timeSource, on: hit.day, calendar: calendar)
                    results.append(ParsedEvent(day: hit.day, name: name, callTime: time))
                }
                currentDay = hits.count == 1 ? hits[0].day : nil
                last = results.count - 1
                pending = (hits.count == 1 && shared.isEmpty) ? last : nil
                continue
            }

            // A line with no date belongs to the last date line.
            guard let day = currentDay else { continue }
            let time = firstTime(in: line, on: day, calendar: calendar)
            let name = clean(line, leadingWeekday: false, trailingWeekday: false)
            if name.isEmpty {
                if let t = time, let i = last, results[i].callTime == nil { results[i].callTime = t }
                continue
            }
            let lower = name.lowercased()
            if isNote(lower) || isHeader(lower) { continue }
            if isDayOff(lower) {
                if pending != nil { results.removeLast() }
                pending = nil; last = nil; currentDay = nil
                continue
            }
            if let i = pending {
                results[i].name = name
                if results[i].callTime == nil { results[i].callTime = time }
                pending = nil
            } else if time != nil {
                // Another event on the same day, listed under the date with its own time.
                // Lines without a time ("Wear black") are notes, not events.
                results.append(ParsedEvent(day: day, name: name, callTime: time))
                last = results.count - 1
            }
        }

        // A date with nothing after it still means you work that day.
        for i in results.indices where results[i].name.isEmpty {
            results[i].name = "Shift"
        }
        return dedupe(results)
    }

    // MARK: - Dates

    private struct DateHit {
        let range: NSRange
        let day: Date
    }

    private static let monthNumbers: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12
    ]

    private static func findDates(in line: String, today: Date, calendar: Calendar) -> [DateHit] {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        var hits: [DateHit] = []

        for m in numericDate.matches(in: line, range: full) {
            let month = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let day = Int(ns.substring(with: m.range(at: 2))) ?? 0
            let year = m.range(at: 3).location != NSNotFound ? Int(ns.substring(with: m.range(at: 3))) : nil
            if let d = makeDay(month: month, day: day, year: year, today: today, calendar: calendar) {
                hits.append(DateHit(range: m.range, day: d))
            }
        }
        for m in namedDate.matches(in: line, range: full) {
            if hits.contains(where: { NSIntersectionRange($0.range, m.range).length > 0 }) { continue }
            let key = String(ns.substring(with: m.range(at: 1)).lowercased().prefix(3))
            guard let month = monthNumbers[key] else { continue }
            let day = Int(ns.substring(with: m.range(at: 2))) ?? 0
            let year = m.range(at: 3).location != NSNotFound ? Int(ns.substring(with: m.range(at: 3))) : nil
            if let d = makeDay(month: month, day: day, year: year, today: today, calendar: calendar) {
                hits.append(DateHit(range: m.range, day: d))
            }
        }
        return hits.sorted { $0.range.location < $1.range.location }
    }

    /// With no year, picks the year that puts the date closest to today (so a January schedule pasted in December lands in next year).
    private static func makeDay(month: Int, day: Int, year: Int?, today: Date, calendar: Calendar) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        func build(_ y: Int) -> Date? {
            var c = DateComponents()
            c.year = y
            c.month = month
            c.day = day
            guard let d = calendar.date(from: c),
                  calendar.component(.month, from: d) == month,
                  calendar.component(.day, from: d) == day else { return nil }
            return calendar.startOfDay(for: d)
        }
        if var y = year {
            if y < 100 { y += 2000 }
            return build(y)
        }
        let thisYear = calendar.component(.year, from: today)
        let options = [thisYear - 1, thisYear, thisYear + 1].compactMap { build($0) }
        return options.min { abs($0.timeIntervalSince(today)) < abs($1.timeIntervalSince(today)) }
    }

    // MARK: - Times

    private static func firstTime(in text: String, on day: Date, calendar: Calendar) -> Date? {
        let ns = text as NSString
        guard let m = timeRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        var hour = 0
        var minute = 0
        if let h = group(1) {
            hour = Int(h) ?? 0
            minute = Int(group(2) ?? "0") ?? 0
            let pm = (group(3) ?? "").lowercased() == "p"
            guard (1...12).contains(hour) else { return nil }
            if hour == 12 {
                hour = pm ? 12 : 0
            } else if pm {
                hour += 12
            }
        } else if let h = group(4) {
            hour = Int(h) ?? 0
            minute = Int(group(5) ?? "0") ?? 0
            // "5:30" with no AM/PM on an arena schedule is almost always evening.
            if (1...6).contains(hour) { hour += 12 }
        } else {
            return nil
        }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    // MARK: - Cleaning up names

    private static func clean(_ text: String, leadingWeekday: Bool, trailingWeekday: Bool) -> String {
        var t = replace(timeRemoval, in: text, with: " ")
        if leadingWeekday { t = replace(leadingWeekdayRegex, in: t, with: " ") }
        if trailingWeekday { t = replace(trailingWeekdayRegex, in: t, with: " ") }
        return tidy(t)
    }

    private static let separators = CharacterSet(charactersIn: " \t-–—:|,;·•*_#>~=/").union(.whitespacesAndNewlines)

    private static func tidy(_ s: String) -> String {
        var t = replace(emptyBrackets, in: s, with: " ")
        t = replace(spaceBeforeClose, in: t, with: ")")
        t = replace(spaceAfterOpen, in: t, with: "(")
        t = replace(multiSpace, in: t, with: " ")
        t = t.trimmingCharacters(in: separators)
        while t.hasSuffix("(") || t.hasSuffix("[") {
            t.removeLast()
            t = t.trimmingCharacters(in: separators)
        }
        while t.hasPrefix(")") || t.hasPrefix("]") {
            t.removeFirst()
            t = t.trimmingCharacters(in: separators)
        }
        if t.hasPrefix("("), !t.contains(")") { t.removeFirst() }
        if t.hasSuffix(")"), !t.contains("(") { t.removeLast() }
        t = t.trimmingCharacters(in: separators)
        // "Event: Martin Lawrence" → "Martin Lawrence"
        let ns = t as NSString
        if let m = nameLabel.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) {
            t = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: separators)
        }
        if t.rangeOfCharacter(from: .letters) == nil { return "" }
        return t
    }

    private static func stripMarkdown(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
        t = replace(heading, in: t, with: "")
        t = replace(bullet, in: t, with: "")
        t = replace(checkbox, in: t, with: "")
        return t
    }

    private static let headerWords: Set<String> = [
        "schedule", "my schedule", "work schedule", "events", "upcoming", "upcoming events",
        "calendar", "month", "shifts", "my shifts", "work"
    ]

    private static func isHeader(_ lower: String) -> Bool {
        lower.hasPrefix("week") || lower.hasPrefix("schedule for") || lower.hasPrefix("pay period")
            || headerWords.contains(lower)
    }

    private static let dayOffWords: Set<String> = [
        "off", "day off", "off day", "no event", "no events", "no shift", "no shifts", "not scheduled",
        "none", "nothing", "free", "rest", "n/a", "na", "x"
    ]

    private static func isDayOff(_ lower: String) -> Bool {
        dayOffWords.contains(lower)
    }

    private static let noteLabels: Set<String> = [
        "position", "role", "job", "location", "where", "gate", "section", "area", "post", "stand",
        "uniform", "dress", "dress code", "attire", "wear", "note", "notes", "parking", "supervisor",
        "manager", "lead", "dept", "department", "pay", "rate", "details", "address", "venue", "meet",
        "entrance", "bring", "duties", "assignment", "hours", "shift", "doors", "show", "call", "end", "out"
    ]

    private static func isNote(_ lower: String) -> Bool {
        guard let colon = lower.firstIndex(of: ":") else { return false }
        let label = lower[..<colon].trimmingCharacters(in: .whitespaces)
        return noteLabels.contains(label)
    }

    private static func dedupe(_ events: [ParsedEvent]) -> [ParsedEvent] {
        var seen = Set<String>()
        var out: [ParsedEvent] = []
        for e in events {
            let key = "\(Int(e.day.timeIntervalSinceReferenceDate))|\(e.name.lowercased())"
            if seen.insert(key).inserted { out.append(e) }
        }
        return out.sorted { ($0.callTime ?? $0.day) < ($1.callTime ?? $1.day) }
    }

    // MARK: - Patterns (case-insensitive)

    private static let weekday =
        #"(?:mon(?:day)?|tue(?:s(?:day)?)?|wed(?:s|nesday)?|thu(?:r(?:s(?:day)?)?)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)"#
    private static let t12 = #"(?<![\d:])\d{1,2}(?::[0-5]\d)?\s?[ap]\.?(?:m\.?)?(?![a-z])"#
    private static let t24 = #"(?<![\d:])(?:[01]?\d|2[0-3]):[0-5]\d(?!\d)"#

    private static let numericDate = regex(#"(?<![\d/])(\d{1,2})/(\d{1,2})(?:/(\d{4}|\d{2}))?(?![\d/])"#)
    private static let namedDate = regex(
        #"\b(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?!\d)(?:,?\s+(\d{4})(?!\d))?"#
    )
    private static let timeRegex = regex(
        #"(?:(?<![\d:])(\d{1,2})(?::([0-5]\d))?\s?([ap])\.?(?:m\.?)?(?![a-z]))|(?:(?<![\d:])([01]?\d|2[0-3]):([0-5]\d)(?!\d))"#
    )
    private static let timeRemoval: NSRegularExpression = {
        let anyTime = "(?:" + ScheduleParser.t12 + "|" + ScheduleParser.t24 + ")"
        let prefix = #"(?:\b(?:call\s*time|call|doors?|show\s*time|showtime|show|start\s*time|starts?|arrive|arrival|report|shift|work|hours|(?:check|clock|load)[\s-]*(?:in|out)|in|at)\b\s*:?\s*|@\s*)?"#
        let range = #"(?:\s*(?:-|–|—|to|until|till|til)\s*"# + anyTime + ")?"
        return ScheduleParser.regex(prefix + anyTime + range)
    }()
    private static let leadingWeekdayRegex = regex(#"^[\s,.(\[\-–—:|·•]*"# + weekday + #"\b\.?[)\]]?"#)
    private static let trailingWeekdayRegex = regex(#"[\s,(\[\-–—:|·•]*\b"# + weekday + #"\b\.?[)\]]?[\s,.\-–—:|·•]*$"#)
    private static let bullet = regex(#"^\s*(?:[-*•+>▪◦‣–—]|\d{1,2}[.)])\s+"#)
    private static let heading = regex(#"^\s*#+\s*"#)
    private static let checkbox = regex(#"^\s*\[[ x]?\]\s*"#)
    private static let emptyBrackets = regex(#"[(\[]\s*[)\]]"#)
    private static let spaceBeforeClose = regex(#"\s+\)"#)
    private static let spaceAfterOpen = regex(#"\(\s+"#)
    private static let multiSpace = regex(#"\s{2,}"#)
    private static let nameLabel = regex(#"^(?:event|show|artist|performer|name|title|act)\s*:\s*(.+)$"#)

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Fixed patterns; a bad one is a programming error caught by the tests.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func replace(_ re: NSRegularExpression, in s: String, with template: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
    }

}
