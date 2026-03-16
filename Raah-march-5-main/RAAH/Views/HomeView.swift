import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            // Pitch black — the Earth orb is the only light source
            Color.black.ignoresSafeArea()

            // Earth Orb — centered, sole interactive element
            EarthOrbView(
                voiceState: appState.realtimeService.voiceState,
                size: 240
            )
            .onTapGesture(count: 3) {
                appState.triggerSOS()
            }
            .onTapGesture {
                HapticEngine.medium()
                switch appState.realtimeService.voiceState {
                case .speaking, .thinking:
                    appState.realtimeService.cancelCurrentResponse()
                case .paused:
                    appState.realtimeService.resumeAudioCapture()
                default:
                    if appState.realtimeService.isConnected {
                        appState.endVoiceSession()
                    } else {
                        appState.startVoiceSession()
                    }
                }
            }

            // Safety alert banner (safety-critical — kept)
            if appState.showingSafetyAlert {
                safetyBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // SOS countdown overlay (safety-critical — kept)
            if appState.isSOSCountdownActive {
                sosCountdownOverlay
                    .transition(.opacity)
            }
        }
        .animation(RAAHTheme.Motion.smooth, value: appState.showingSafetyAlert)
        .animation(RAAHTheme.Motion.snappy, value: appState.isSOSCountdownActive)
        .onChange(of: appState.pendingVoiceStart) { _, should in
            if should {
                appState.pendingVoiceStart = false
                if !appState.realtimeService.isConnected {
                    appState.startVoiceSession()
                }
            }
        }
    }

    // MARK: - Safety Banner

    private var safetyBanner: some View {
        VStack {
            GlassCard(padding: RAAHTheme.Spacing.md) {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Safety Alert")
                            .font(RAAHTheme.Typography.headline())
                        Text("You've entered an area with lower safety ratings")
                            .font(RAAHTheme.Typography.caption())
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        appState.showingSafetyAlert = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                }
            }
            .padding(.horizontal, RAAHTheme.Spacing.lg)
            .padding(.top, RAAHTheme.Spacing.sm)

            Spacer()
        }
    }

    // MARK: - SOS Countdown

    private var sosCountdownOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "sos")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(.red)

                Text("Sending SOS in \(appState.sosCountdownSeconds)...")
                    .font(RAAHTheme.Typography.title2())
                    .foregroundStyle(.white)

                Button {
                    appState.cancelSOS()
                } label: {
                    Text("Cancel")
                        .font(RAAHTheme.Typography.headline())
                        .foregroundStyle(.white)
                        .frame(width: 160)
                        .padding(.vertical, 14)
                        .background { Capsule().fill(Color.white.opacity(0.2)) }
                        .overlay { Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
