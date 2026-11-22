import AppIntents
import UserNotifications

/// Runs in the background (never opens the app). Hook it to the NFC sticker in Shortcuts.
struct ToggleShiftIntent: AppIntent {
    static var title: LocalizedStringResource = "Clock In/Out"
    static var description = IntentDescription("Clocks you out (you're clocked in automatically at your scheduled start). On a day with nothing scheduled it clocks you in. Runs in the background.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = ClockActions.toggleShift()
        return .result(dialog: "\(message)")
    }
}

/// Runs in the background. Put it on the Action button.
struct ToggleLunchIntent: AppIntent {
    static var title: LocalizedStringResource = "Lunch"
    static var description = IntentDescription("Starts or ends your lunch and sets the lunch reminders. Runs in the background.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        var message = ClockActions.toggleLunch()
        if message.hasPrefix("Lunch started") {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus != .authorized && settings.authorizationStatus != .provisional {
                message += " · reminders are off, open ABI Hours to allow them"
            }
        }
        return .result(dialog: "\(message)")
    }
}

/// Makes both actions show up in Shortcuts, the Action button picker and Spotlight (search "abi").
struct ABIHoursShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleShiftIntent(),
            phrases: [
                "Clock in with \(.applicationName)",
                "Clock out with \(.applicationName)",
                "Toggle my shift in \(.applicationName)"
            ],
            shortTitle: "Clock In/Out",
            systemImageName: "clock.badge.checkmark"
        )
        AppShortcut(
            intent: ToggleLunchIntent(),
            phrases: [
                "Start lunch in \(.applicationName)",
                "End lunch in \(.applicationName)",
                "Toggle lunch in \(.applicationName)"
            ],
            shortTitle: "Lunch",
            systemImageName: "fork.knife"
        )
    }
}
