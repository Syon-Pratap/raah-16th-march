import AppIntents

struct StartRAHHIntent: AppIntent {
    static var title: LocalizedStringResource = "Start RAAH"
    static var description = IntentDescription("Open RAAH and start a voice conversation with your AI companion")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // Signal the app to auto-start the voice session when it opens
        UserDefaults.standard.set(true, forKey: "raah_auto_start_voice")
        return .result()
    }
}

struct RAHHShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRAHHIntent(),
            phrases: [
                "Start \(.applicationName)",
                "Open \(.applicationName)",
                "Talk to \(.applicationName)",
                "Hey \(.applicationName)"
            ],
            shortTitle: "Start RAAH",
            systemImageName: "waveform.circle.fill"
        )
    }
}
