import SwiftUI

/// Paste the plain-text schedule, check what was read, save.
struct SchedulePasteView: View {
    @EnvironmentObject private var store: ShiftStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var parsed: [ParsedEvent] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .font(.callout)
                        .frame(minHeight: 180)
                    PasteButton(payloadType: String.self) { strings in
                        let pasted = strings.joined(separator: "\n")
                        DispatchQueue.main.async { text = pasted }
                    }
                } header: {
                    Text("Your schedule")
                } footer: {
                    Text("Plain text works best, like \"Thu 11/20 — Martin Lawrence — call 5:00 PM\". Pasting days you already loaded replaces them, so you can paste an updated schedule anytime.")
                }

                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section {
                        if parsed.isEmpty {
                            Text("No dates found yet. Each event needs a date like 11/20 or Nov 20.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach($parsed) { $event in
                            VStack(alignment: .leading, spacing: 2) {
                                TextField("Event name", text: $event.name)
                                    .font(.body.weight(.semibold))
                                Text(subtitle(event))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { offsets in
                            parsed.remove(atOffsets: offsets)
                        }
                    } header: {
                        Text(parsed.count == 1 ? "Found 1 event" : "Found \(parsed.count) events")
                    } footer: {
                        Text("Tap a name to fix it. Swipe left to remove one.")
                    }
                }
            }
            .navigationTitle("Paste schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(parsed.isEmpty)
                }
            }
            .onChange(of: text) { _, newText in
                parsed = ScheduleParser.parse(newText)
            }
        }
    }

    private func subtitle(_ event: ParsedEvent) -> String {
        var s = Fmt.day(event.day)
        if let t = event.callTime { s += " · call \(Fmt.time(t))" }
        return s
    }

    private func save() {
        let events = parsed.map { p -> WorkEvent in
            let name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return WorkEvent(day: p.day, name: name.isEmpty ? "Shift" : name, callTime: p.callTime)
        }
        store.importEvents(events)
        dismiss()
    }
}

/// All loaded events, by week. Tap to edit, swipe to delete.
struct EventsView: View {
    @EnvironmentObject private var store: ShiftStore
    @Environment(\.dismiss) private var dismiss
    @State private var showPaste = false
    @State private var editing: WorkEvent?
    @State private var showPast = false

    private struct EventWeek: Identifiable {
        let week: Week
        var events: [WorkEvent]
        var id: Date { week.start }
    }

    var body: some View {
        let today = Calendar.current.startOfDay(for: Date())
        let cutoff = Weeks.week(containing: today).start
        let weeks = Self.group(store.events.filter { showPast || $0.day >= cutoff })

        List {
            Section {
                Button {
                    showPaste = true
                } label: {
                    Label("Paste schedule", systemImage: "doc.on.clipboard")
                }
                Button {
                    editing = WorkEvent(day: today, name: "")
                } label: {
                    Label("Add an event", systemImage: "plus")
                }
                Toggle("Show past events", isOn: $showPast)
            }

            if weeks.isEmpty {
                Section {
                    Text("No events yet. Paste the plain-text schedule Claude made you.")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(weeks) { entry in
                Section(entry.week.title) {
                    ForEach(entry.events) { event in
                        Button {
                            editing = event
                        } label: {
                            EventRow(event: event)
                        }
                        .tint(.primary)
                    }
                    .onDelete { offsets in
                        for i in offsets { store.deleteEvent(id: entry.events[i].id) }
                    }
                }
            }
        }
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $showPaste) {
            SchedulePasteView().environmentObject(store)
        }
        .sheet(item: $editing) { event in
            EventEditView(event: event).environmentObject(store)
        }
    }

    private static func group(_ events: [WorkEvent]) -> [EventWeek] {
        var byStart: [Date: EventWeek] = [:]
        for event in events {
            let w = Weeks.week(containing: event.day)
            byStart[w.start, default: EventWeek(week: w, events: [])].events.append(event)
        }
        return byStart.values
            .map { entry in
                var e = entry
                e.events.sort { $0.sortDate < $1.sortDate }
                return e
            }
            .sorted { $0.week.start < $1.week.start }
    }
}

struct EventRow: View {
    let event: WorkEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(event.name).font(.body.weight(.semibold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        var s = Fmt.day(event.day)
        if let t = event.callTime { s += " · call \(Fmt.time(t))" }
        return s
    }
}

struct EventEditView: View {
    @EnvironmentObject private var store: ShiftStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WorkEvent
    @State private var hasCallTime: Bool

    init(event: WorkEvent) {
        _draft = State(initialValue: event)
        _hasCallTime = State(initialValue: event.callTime != nil)
    }

    private var exists: Bool { store.events.contains { $0.id == draft.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Event name", text: $draft.name)
                    DatePicker("Date", selection: $draft.day, displayedComponents: .date)
                    Toggle("Call time", isOn: $hasCallTime)
                    if hasCallTime {
                        DatePicker("Time", selection: callBinding, displayedComponents: .hourAndMinute)
                    }
                }
                if exists {
                    Section {
                        Button("Delete event", role: .destructive) {
                            store.deleteEvent(id: draft.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(exists ? "Edit event" : "New event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var callBinding: Binding<Date> {
        Binding(
            get: {
                draft.callTime
                    ?? Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: draft.day)
                    ?? draft.day
            },
            set: { draft.callTime = $0 }
        )
    }

    private func save() {
        let cal = Calendar.current
        var e = draft
        e.day = cal.startOfDay(for: e.day)
        e.name = e.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasCallTime {
            // Keep the call time on the event's day even if the date was changed.
            let parts = cal.dateComponents([.hour, .minute], from: callBinding.wrappedValue)
            e.callTime = cal.date(bySettingHour: parts.hour ?? 17, minute: parts.minute ?? 0, second: 0, of: e.day)
        } else {
            e.callTime = nil
        }
        store.addOrUpdateEvent(e)
        dismiss()
    }
}
