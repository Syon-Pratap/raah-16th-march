import SwiftUI

@main
struct RAAHApp: App {

    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .tint(appState.accentColor)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        // Restart location in case iOS paused it while backgrounded/stationary
                        appState.locationManager.startTracking()
                        if appState.locationManager.hasRealLocation {
                            appState.refreshContext()
                        }
                        // Triggered by App Intent (Siri / Action button)
                        if UserDefaults.standard.bool(forKey: "raah_auto_start_voice") {
                            UserDefaults.standard.removeObject(forKey: "raah_auto_start_voice")
                            appState.selectedTab = .home
                            appState.pendingVoiceStart = true
                        }
                    } else if phase == .background {
                        if !appState.realtimeService.isConnected {
                            appState.locationManager.setLowAccuracy()
                        }
                    }
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "raah" else { return }

        switch url.host {
        case "start":
            // Triggered by lock screen widget tap
            appState.selectedTab = .home
            appState.pendingVoiceStart = true
        case "poi":
            appState.selectedTab = .explore
        default:
            break
        }
    }
}
