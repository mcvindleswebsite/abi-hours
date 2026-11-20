import SwiftUI

struct ShiftEditView: View {
    @EnvironmentObject private var store: ShiftStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Shift
    @State private var confirmDelete = false
    private let original: Shift
    private let isNew: Bool

    init(shift: Shift, isNew: Bool) {
        self.original = shift
        self.isNew = isNew
        _draft = State(initialValue: shift)
    }

    var body: some View {
        NavigationStack {
            Form {
                if draft.missingClockOut {
                    Section {
                        Label("You never tapped out of this shift. Set the time you actually left.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section("Event") {
                    Picker("Event", selection: $draft.eventID) {
                        Text(autoLabel).tag(UUID?.none)
                        ForEach(nearbyEvents) { event in
                            Text("\(event.name) · \(Fmt.shortDay(event.day))").tag(UUID?.some(event.id))
                        }
                    }
                }

                Section("Shift") {
                    DatePicker("Clock in", selection: $draft.start)
                    if draft.end != nil {
                        DatePicker("Clock out", selection: endBinding, in: draft.start...)
                    } else {
                        LabeledContent("Clock out", value: "Still clocked in")
                        Button("Clock out now") {
                            draft.end = max(Date(), draft.start)
                        }
                    }
                }

                Section("Lunch") {
                    ForEach($draft.lunches) { $lunch in
                        VStack(alignment: .leading, spacing: 6) {
                            DatePicker("Start", selection: $lunch.start)
                            if lunch.end != nil {
                                DatePicker("End",
                                           selection: Binding(get: { lunch.end ?? lunch.start },
                                                              set: { $lunch.wrappedValue.end = $0 }),
                                           in: lunch.start...)
                            } else {
                                Button("End lunch now") {
                                    $lunch.wrappedValue.end = max(Date(), lunch.start)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        draft.lunches.remove(atOffsets: offsets)
                    }
                    Button("Add a lunch") { addLunch() }
                }

                Section {
                    LabeledContent("Hours worked", value: Fmt.duration(draft.workedSeconds()))
                }

                if !isNew {
                    Section {
                        Button("Delete shift", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "Add shift" : "Edit shift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .confirmationDialog("Delete this shift?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.deleteShift(id: original.id)
                    if original.openLunch != nil { Notifier.cancelLunch() }
                    dismiss()
                }
            }
        }
    }

    private var autoLabel: String {
        "Auto · " + (store.autoEvent(for: draft.start)?.name ?? "no event that day")
    }

    /// Events within two days of the shift, so a late-night shift can still be pointed at the right one.
    private var nearbyEvents: [WorkEvent] {
        let day = Calendar.current.startOfDay(for: draft.start)
        return store.events.filter { abs($0.day.timeIntervalSince(day)) <= 2 * 86_400 }
    }

    private var endBinding: Binding<Date> {
        Binding(get: { draft.end ?? draft.start }, set: { draft.end = $0 })
    }

    private func addLunch() {
        let end = draft.end ?? Date()
        let middle = draft.start.addingTimeInterval(max(0, end.timeIntervalSince(draft.start)) / 2)
        let length = TimeInterval(AppSettings.lunchMinutes * 60)
        draft.lunches.append(Lunch(start: middle, end: middle.addingTimeInterval(length)))
    }

    private func save() {
        var s = draft
        if let end = s.end {
            if end < s.start { s.end = s.start }
            if end > s.start { s.missingClockOut = false }
            for i in s.lunches.indices where s.lunches[i].end == nil {
                s.lunches[i].end = s.end
            }
        }
        for i in s.lunches.indices {
            if let e = s.lunches[i].end, e < s.lunches[i].start {
                s.lunches[i].end = s.lunches[i].start
            }
        }
        s.lunches.sort { $0.start < $1.start }
        store.addOrUpdate(s)
        if original.openLunch != nil && s.openLunch == nil {
            Notifier.cancelLunch()
        }
        dismiss()
    }
}
