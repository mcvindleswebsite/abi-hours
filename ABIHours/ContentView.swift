import SwiftUI

enum ActiveSheet: Identifiable {
    case edit(Shift)
    case add(Shift)
    case settings
    case schedule
    case paste

    var id: String {
        switch self {
        case .edit(let s): return "edit-\(s.id.uuidString)"
        case .add(let s): return "add-\(s.id.uuidString)"
        case .settings: return "settings"
        case .schedule: return "schedule"
        case .paste: return "paste"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: ShiftStore
    @AppStorage(Weeks.startDayKey) private var weekStart = 2
    @State private var sheet: ActiveSheet?
    @State private var expanded: Set<Date> = [Weeks.week(containing: Date()).start]

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                content(now: context.date)
            }
            .navigationTitle("ABI Hours")
            .toolbar { toolbarContent }
            .sheet(item: $sheet) { which in
                sheetView(which)
            }
        }
        .onAppear {
            Notifier.requestPermission()
            store.closeStaleShifts()
        }
        .onChange(of: weekStart) { _, _ in
            expanded = [Weeks.week(containing: Date()).start]
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let weeks = store.weekGroups(now: now)
        let thisWeekStart = Weeks.week(containing: now).start
        let current = weeks.filter { $0.week.start == thisWeekStart }
        let upcoming = weeks
            .filter { $0.week.start > thisWeekStart }
            .sorted { $0.week.start < $1.week.start }
        let past = weeks
            .filter { $0.week.start < thisWeekStart && !$0.items.isEmpty }
            .sorted { $0.week.start > $1.week.start }

        List {
            Section {
                StatusHeader(now: now)
                Button {
                    _ = ClockActions.toggleShift()
                } label: {
                    Label(store.openShift == nil ? "Clock in" : "Clock out",
                          systemImage: store.openShift == nil ? "play.circle.fill" : "stop.circle.fill")
                }
                Button {
                    _ = ClockActions.toggleLunch()
                } label: {
                    Label(store.openShift?.openLunch == nil ? "Start lunch" : "End lunch", systemImage: "fork.knife")
                }
                .disabled(store.openShift == nil)
            } footer: {
                Text("You don't need to open the app. Tap your badge sticker to clock in or out, and press the Action button for lunch.")
            }

            Section("This week") {
                ForEach(current) { group in
                    WeekDisclosure(group: group, now: now, isExpanded: expandedBinding(group.week.start)) { shift in
                        sheet = .edit(shift)
                    }
                }
            }

            if !upcoming.isEmpty {
                Section("Coming up") {
                    ForEach(upcoming) { group in
                        WeekDisclosure(group: group, now: now, isExpanded: expandedBinding(group.week.start)) { shift in
                            sheet = .edit(shift)
                        }
                    }
                }
            }

            if !past.isEmpty {
                Section("Past weeks") {
                    ForEach(past) { group in
                        WeekDisclosure(group: group, now: now, isExpanded: expandedBinding(group.week.start)) { shift in
                            sheet = .edit(shift)
                        }
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                sheet = .settings
            } label: {
                Image(systemName: "gearshape")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    sheet = .paste
                } label: {
                    Label("Add schedule", systemImage: "calendar.badge.plus")
                }
                Button {
                    sheet = .schedule
                } label: {
                    Label("Schedule", systemImage: "calendar")
                }
                Button {
                    sheet = .add(Shift.newManual())
                } label: {
                    Label("Add a shift", systemImage: "plus")
                }
                ShareLink(item: CSVFile(text: store.csv()), preview: SharePreview("ABI Hours.csv")) {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    @ViewBuilder
    private func sheetView(_ which: ActiveSheet) -> some View {
        switch which {
        case .edit(let shift):
            ShiftEditView(shift: shift, isNew: false).environmentObject(store)
        case .add(let shift):
            ShiftEditView(shift: shift, isNew: true).environmentObject(store)
        case .settings:
            SettingsView()
        case .schedule:
            NavigationStack { EventsView() }.environmentObject(store)
        case .paste:
            SchedulePasteView().environmentObject(store)
        }
    }

    private func expandedBinding(_ weekStart: Date) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(weekStart) },
            set: { isOpen in
                if isOpen { expanded.insert(weekStart) } else { expanded.remove(weekStart) }
            }
        )
    }
}

// MARK: - Status

struct StatusHeader: View {
    @EnvironmentObject private var store: ShiftStore
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let shift = store.openShift {
                let eventName = store.event(for: shift)?.name
                if let lunch = shift.openLunch {
                    Label("On lunch", systemImage: "fork.knife")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text("Since \(Fmt.time(lunch.start)) · back by \(Fmt.time(lunch.start.addingTimeInterval(TimeInterval(AppSettings.lunchMinutes * 60))))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Label(eventName.map { "Clocked in · \($0)" } ?? "Clocked in", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text("Since \(Fmt.time(shift.start)) · \(Fmt.duration(shift.workedSeconds(now: now))) so far")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("Off the clock", systemImage: "moon.zzz.fill")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                if let next = store.nextEvent(from: now) {
                    Text(nextLine(next))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func nextLine(_ event: WorkEvent) -> String {
        let call = event.callTime.map { " · call \(Fmt.time($0))" } ?? ""
        if Calendar.current.isDateInToday(event.day) {
            return "Today: \(event.name)\(call)"
        }
        return "Next: \(Fmt.day(event.day)) · \(event.name)\(call)"
    }
}

// MARK: - Week → events → shifts

struct WeekDisclosure: View {
    let group: WeekGroup
    let now: Date
    @Binding var isExpanded: Bool
    let onSelect: (Shift) -> Void

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if group.items.isEmpty {
                Text("Nothing yet. Add your schedule from the ⋯ menu.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(group.items) { item in
                EventDisclosure(item: item, now: now, onSelect: onSelect)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.week.title).font(.headline)
                    Text(countLine).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Fmt.hours(group.worked(now: now)))
                    .font(.subheadline.monospacedDigit())
            }
        }
    }

    private var countLine: String {
        let n = group.items.filter { $0.event != nil }.count
        return n == 1 ? "1 event" : "\(n) events"
    }
}

struct EventDisclosure: View {
    let item: EventGroup
    let now: Date
    let onSelect: (Shift) -> Void

    var body: some View {
        DisclosureGroup {
            if item.shifts.isEmpty {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(item.shifts) { shift in
                Button {
                    onSelect(shift)
                } label: {
                    ShiftRow(shift: shift, now: now)
                }
                .tint(.primary)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                trailing
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if !item.shifts.isEmpty {
            Text(Fmt.duration(item.worked(now: now)))
                .font(.subheadline.monospacedDigit())
        } else if Calendar.current.isDateInToday(item.day) {
            Text("Today")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
        }
    }

    private var subtitle: String {
        var text = Fmt.day(item.day)
        if let call = item.event?.callTime {
            text += " · call \(Fmt.time(call))"
        }
        return text
    }

    private var emptyText: String {
        if Calendar.current.isDateInToday(item.day) { return "Not clocked in yet" }
        return item.day > now ? "Upcoming" : "No hours logged"
    }
}

struct ShiftRow: View {
    let shift: Shift
    let now: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(timeRange).font(.subheadline)
                if shift.missingClockOut {
                    Label("Missing clock-out · tap to fix", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if shift.lunchSeconds(now: now) > 0 {
                    Text("Lunch \(Fmt.duration(shift.lunchSeconds(now: now)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(Fmt.duration(shift.workedSeconds(now: now)))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var timeRange: String {
        let start = Fmt.time(shift.start)
        if shift.missingClockOut { return "\(start) – ?" }
        guard let end = shift.end else { return "\(start) – now" }
        return "\(start) – \(Fmt.time(end))"
    }
}
