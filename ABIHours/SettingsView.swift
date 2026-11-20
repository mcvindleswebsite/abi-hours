import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.lunchKey) private var lunchMinutes = 30
    @AppStorage(AppSettings.headsUpKey) private var headsUpMinutes = 5
    @AppStorage(Weeks.startDayKey) private var weekStart = 2
    @State private var status: UNAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $lunchMinutes, in: 10...90, step: 5) {
                        Text("Lunch length: \(lunchMinutes) min")
                    }
                    Stepper(value: $headsUpMinutes, in: 0...15) {
                        Text(headsUpLabel)
                    }
                } header: {
                    Text("Lunch")
                } footer: {
                    Text("You get a heads-up before lunch ends and a reminder when it's over. Changes apply to your next lunch.")
                }

                Section {
                    Picker("Week starts on", selection: $weekStart) {
                        ForEach(1...7, id: \.self) { day in
                            Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                        }
                    }
                } header: {
                    Text("Weeks")
                } footer: {
                    Text("Set this to your pay week so weekly totals line up with ABI.")
                }

                Section("Notifications") {
                    notificationRow
                }

                Section {
                    NavigationLink("Set up the badge sticker & Action button") {
                        SetupGuideView()
                    }
                }

                Section {
                    Text("Everything stays on this phone. Use ⋯ → Export CSV to back up your hours.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await refreshStatus() }
        }
    }

    private var headsUpLabel: String {
        headsUpMinutes == 0 ? "Heads-up: off" : "Heads-up: \(headsUpMinutes) min before"
    }

    @ViewBuilder
    private var notificationRow: some View {
        switch status {
        case .authorized, .provisional, .ephemeral:
            Label("Lunch reminders are on", systemImage: "bell.fill")
        case .denied:
            Label("Notifications are off for ABI Hours", systemImage: "bell.slash")
                .foregroundStyle(.orange)
            Button("Open iPhone Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        default:
            Button("Turn on lunch reminders") {
                Task {
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                    await refreshStatus()
                }
            }
        }
    }

    private func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        status = settings.authorizationStatus
    }
}

struct SetupGuideView: View {
    var body: some View {
        List {
            Section {
                GuideStep(number: 1, text: "Stick an NFC sticker on the back of your work ID. You don't need to write anything to it.")
                GuideStep(number: 2, text: "Open **Shortcuts** → **Automation** → **+** → **NFC** → **Scan**, and hold the top of your phone to the sticker. Name it \"Work badge\".")
                GuideStep(number: 3, text: "Choose **Run Immediately** and turn off **Notify When Run**.")
                GuideStep(number: 4, text: "Tap **Create New Shortcut** (or **New Blank Automation**), add an action, search **ABI Hours**, and pick **Clock In/Out**.")
                GuideStep(number: 5, text: "At work: scan your ID at the ABI scanner, then tap your phone to the sticker. Same thing when you leave.")
            } header: {
                Text("Badge sticker → clock in/out")
            }

            Section {
                GuideStep(number: 1, text: "Open **Settings** → **Action Button**, swipe to **Shortcut**, tap **Choose a Shortcut**, then pick **ABI Hours** → **Lunch**.")
                GuideStep(number: 2, text: "Press and hold the Action button for about a second to start lunch. Do it again to end it.")
                GuideStep(number: 3, text: "You get a heads-up 5 minutes before lunch ends and a reminder when it's over. Both have an **End lunch** button too.")
            } header: {
                Text("Action button → lunch")
            }

            Section {
                GuideStep(number: 1, text: "Get the plain-text version of your schedule (the one Claude writes for you).")
                GuideStep(number: 2, text: "In ABI Hours, tap **⋯** → **Paste schedule**, paste it, check the events it found, and tap **Save**.")
                GuideStep(number: 3, text: "From then on, every shift is labeled with that day's event automatically.")
            } header: {
                Text("Your schedule")
            }

            Section {
                Text("If ABI Hours doesn't show up in Shortcuts, open the app once and try again.")
                Text("A second tap within 10 seconds is ignored, so bumping the sticker won't clock you back out.")
                Text("Forgot to clock out? After 16 hours the shift is flagged. Tap it to set the real time.")
                Text("Using a Focus at work? Allow ABI Hours in it so lunch reminders come through.")
            } header: {
                Text("Good to know")
            }
            .font(.subheadline)
        }
        .navigationTitle("Setup")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct GuideStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
            Text(LocalizedStringKey(text))
        }
        .padding(.vertical, 2)
    }
}
