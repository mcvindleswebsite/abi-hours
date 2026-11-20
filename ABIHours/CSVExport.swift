import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Shared from ⋯ → Export CSV. The file is only written when you actually share it.
struct CSVFile: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("ABI Hours.csv")
            try file.text.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}

extension ShiftStore {
    func csv(now: Date = Date()) -> String {
        let dayFormat = DateFormatter()
        dayFormat.locale = Locale(identifier: "en_US_POSIX")
        dayFormat.dateFormat = "yyyy-MM-dd"
        let timeFormat = DateFormatter()
        timeFormat.locale = Locale(identifier: "en_US_POSIX")
        timeFormat.dateFormat = "h:mm a"

        var lines = ["Date,Event,Clock In,Clock Out,Lunch (min),Hours,Notes"]
        for s in shifts {
            var notes: [String] = []
            if s.missingClockOut { notes.append("missing clock-out") }
            if s.end == nil { notes.append("still clocked in") }
            let row = [
                dayFormat.string(from: s.start),
                Self.field(event(for: s)?.name ?? ""),
                timeFormat.string(from: s.start),
                s.end.map { timeFormat.string(from: $0) } ?? "",
                String(Int(s.lunchSeconds(now: now) / 60)),
                String(format: "%.2f", s.workedSeconds(now: now) / 3600),
                Self.field(notes.joined(separator: "; "))
            ]
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func field(_ s: String) -> String {
        guard s.contains(",") || s.contains("\"") || s.contains("\n") else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
