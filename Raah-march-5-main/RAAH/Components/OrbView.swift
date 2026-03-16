import SwiftUI

// MARK: - Main Orb Router

struct OrbView: View {
    let style: OrbStyle
    let accentTheme: AccentTheme
    let voiceState: VoiceState
    let heartRate: Double?
    let size: CGFloat

    var body: some View {
        switch style {
        case .fluid:
            FluidOrbView(accentTheme: accentTheme, voiceState: voiceState, heartRate: heartRate, size: size)
        case .crystal:
            CrystalOrbView(accentTheme: accentTheme, voiceState: voiceState, heartRate: heartRate, size: size)
        case .pulseRing:
            PulseRingOrbView(accentTheme: accentTheme, voiceState: voiceState, heartRate: heartRate, size: size)
        }
    }
}

// MARK: - 1. Fluid Orb — Siri-style, single color, pure breathing

struct FluidOrbView: View {
    let accentTheme: AccentTheme
    let voiceState: VoiceState
    let heartRate: Double?
    let size: CGFloat

    // Continuous loop animations — set once in onAppear, never changed
    @State private var morphPhase: CGFloat = 0
    @State private var breatheToggle = false

    // State-reactive visuals — updated per voiceState change via withAnimation(.spring)
    @State private var glowOpacity: Double = 0.38
    @State private var glowRadius: CGFloat = 28
    @State private var brightnessShift: Double = 0

    // Speaking ring — driven by a Task loop
    @State private var ringPhase: Double = 0
    @State private var ringTask: Task<Void, Never>? = nil

    private var heartBreath: Double {
        guard let hr = heartRate, hr > 0 else { return 4.0 }
        return min(60.0 / hr, 5.0)
    }

    var body: some View {
        ZStack {
            // Outer ambient corona
            Circle()
                .fill(accentTheme.color.opacity(glowOpacity * 0.5))
                .frame(width: size * 2.2, height: size * 2.2)
                .blur(radius: 55)

            // Inner glow halo
            Circle()
                .fill(accentTheme.color.opacity(glowOpacity))
                .frame(width: size * 1.5, height: size * 1.5)
                .blur(radius: glowRadius)

            // Speaking ring — always in layout, invisible when not speaking
            Circle()
                .strokeBorder(
                    accentTheme.color.opacity((1.0 - ringPhase) * 0.5),
                    lineWidth: 1.0
                )
                .frame(
                    width: size * (1.0 + CGFloat(ringPhase) * 0.9),
                    height: size * (1.0 + CGFloat(ringPhase) * 0.9)
                )
                .opacity(voiceState == .speaking ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: voiceState == .speaking)

            // Orb sphere
            ZStack {
                // Base — deep gradient always in accent
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                accentTheme.gradient[0],
                                accentTheme.gradient[1].opacity(0.75),
                                accentTheme.gradient[2].opacity(0.45),
                                Color.black.opacity(0.5),
                            ],
                            center: UnitPoint(
                                x: 0.38 + sin(morphPhase) * 0.1,
                                y: 0.32 + cos(morphPhase * 0.65) * 0.08
                            ),
                            startRadius: 0,
                            endRadius: size * 0.55
                        )
                    )

                // Inner luminance bloom
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                accentTheme.color.opacity(0.5),
                                accentTheme.gradient[1].opacity(0.18),
                                Color.clear
                            ],
                            center: UnitPoint(
                                x: 0.6 + cos(morphPhase * 1.1) * 0.12,
                                y: 0.55 + sin(morphPhase * 0.75) * 0.12
                            ),
                            startRadius: 0,
                            endRadius: size * 0.36
                        )
                    )
                    .blendMode(.plusLighter)

                // Specular highlight — top-left
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.55), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.18
                        )
                    )
                    .frame(width: size * 0.42, height: size * 0.26)
                    .offset(x: -size * 0.09, y: -size * 0.14)

                // Rim light — bottom-right
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [accentTheme.gradient[1].opacity(0.4), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.18
                        )
                    )
                    .frame(width: size * 0.38, height: size * 0.22)
                    .offset(x: size * 0.1, y: size * 0.14)
                    .blendMode(.plusLighter)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .brightness(brightnessShift)
            .shadow(color: accentTheme.color.opacity(0.55), radius: 22, x: 0, y: 0)
            .shadow(color: accentTheme.color.opacity(0.2), radius: 50, x: 0, y: 8)
            // Breathing — driven by breatheToggle via withAnimation(.repeatForever) in onAppear
            .scaleEffect(breatheToggle ? 1.05 : 1.0)
        }
        .onAppear {
            // Slow morph loop — runs forever, never conflicts with state animations
            withAnimation(.linear(duration: 11).repeatForever(autoreverses: false)) {
                morphPhase = .pi * 2
            }
            // Breathing loop — one call, never repeated
            withAnimation(.easeInOut(duration: heartBreath).repeatForever(autoreverses: true)) {
                breatheToggle = true
            }
            // Apply initial visual state
            applyVisuals(voiceState)
        }
        .onChange(of: voiceState) { _, newState in
            // Smooth spring transition for glow/brightness
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                applyVisuals(newState)
            }
            // Ring: start loop when speaking, cancel otherwise
            if newState == .speaking {
                startRingLoop()
            } else {
                ringTask?.cancel()
                ringTask = nil
                ringPhase = 0
            }
        }
        .onDisappear {
            ringTask?.cancel()
            ringTask = nil
        }
    }

    private func applyVisuals(_ state: VoiceState) {
        switch state {
        case .idle:
            glowOpacity = 0.38; glowRadius = 28; brightnessShift = 0
        case .listening:
            glowOpacity = 0.58; glowRadius = 22; brightnessShift = 0.05
        case .thinking:
            glowOpacity = 0.44; glowRadius = 20; brightnessShift = -0.02
        case .speaking:
            glowOpacity = 0.62; glowRadius = 18; brightnessShift = 0.06
        case .reconnecting:
            glowOpacity = 0.30; glowRadius = 30; brightnessShift = -0.05
        case .paused:
            glowOpacity = 0.22; glowRadius = 35; brightnessShift = -0.08
        case .error:
            glowOpacity = 0.22; glowRadius = 35; brightnessShift = -0.10
        }
    }

    /// Repeating ring expansion loop — 0→1 over 2.8s, then resets and repeats
    private func startRingLoop() {
        ringTask?.cancel()
        ringTask = Task { @MainActor in
            while !Task.isCancelled {
                ringPhase = 0
                try? await Task.sleep(for: .milliseconds(40))
                guard !Task.isCancelled else { break }
                withAnimation(.easeOut(duration: 2.8)) {
                    ringPhase = 1.0
                }
                try? await Task.sleep(for: .seconds(3.0))
            }
        }
    }
}

// MARK: - 2. Crystal Orb

struct CrystalOrbView: View {
    let accentTheme: AccentTheme
    let voiceState: VoiceState
    let heartRate: Double?
    let size: CGFloat

    @State private var rotation: Double = 0
    @State private var breatheScale: CGFloat = 1.0

    private var pulseInterval: Double {
        guard let hr = heartRate, hr > 0 else { return 3.0 }
        return 60.0 / hr
    }

    private var activeColor: Color {
        voiceState == .listening ? .green : accentTheme.color
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [activeColor.opacity(0.3), Color.clear],
                        center: .center,
                        startRadius: size * 0.2,
                        endRadius: size * 0.7
                    )
                )
                .frame(width: size * 1.4, height: size * 1.4)
                .blur(radius: 25)

            ForEach(0..<6) { i in
                crystalFacet(index: i)
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.3),
                            activeColor.opacity(0.5),
                            accentTheme.gradient[2].opacity(0.3)
                        ],
                        center: UnitPoint(x: 0.35, y: 0.35),
                        startRadius: 0,
                        endRadius: size * 0.25
                    )
                )
                .frame(width: size * 0.5, height: size * 0.5)
                .shadow(color: activeColor.opacity(0.4), radius: 15)
        }
        .scaleEffect(breatheScale)
        .onAppear {
            withAnimation(.linear(duration: 30).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: pulseInterval).repeatForever(autoreverses: true)) {
                breatheScale = 1.04
            }
        }
    }

    private func crystalFacet(index i: Int) -> some View {
        let secondaryColor = accentTheme.gradient[1]
        let facetSize = size * (0.9 - CGFloat(i) * 0.08)
        let angle = rotation + Double(i) * 15
        return RoundedRectangle(cornerRadius: size * 0.15, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        activeColor.opacity(0.15 - Double(i) * 0.02),
                        secondaryColor.opacity(0.1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: facetSize, height: facetSize)
            .rotationEffect(.degrees(angle))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.15, style: .continuous)
                    .strokeBorder(activeColor.opacity(0.2 - Double(i) * 0.025), lineWidth: 0.5)
                    .rotationEffect(.degrees(angle))
            }
    }
}

// MARK: - Earth Orb — used exclusively on the home screen

struct EarthOrbView: View {
    let voiceState: VoiceState
    let size: CGFloat

    // Continuous loop animations — set once in onAppear
    @State private var rotationDeg: Double = 0
    @State private var breatheToggle: Bool = false

    // State-reactive glow — updated on voiceState change
    @State private var glowOpacity: Double = 0.32

    // Speaking ring — driven by Task loop
    @State private var ringPhase: Double = 0
    @State private var ringTask: Task<Void, Never>? = nil

    // Earth palette
    private let deepOcean  = Color(red: 0.03, green: 0.10, blue: 0.28)
    private let midOcean   = Color(red: 0.05, green: 0.18, blue: 0.44)
    private let landDark   = Color(red: 0.11, green: 0.32, blue: 0.16)
    private let landBright = Color(red: 0.18, green: 0.50, blue: 0.23)
    private let atmosphere = Color(red: 0.38, green: 0.70, blue: 1.00)
    private let iceWhite   = Color(white: 0.92)

    private var glowColor: Color {
        switch voiceState {
        case .listening:  return Color(red: 0.20, green: 0.85, blue: 0.40)
        case .thinking:   return Color(red: 0.30, green: 0.55, blue: 1.00)
        case .speaking:   return atmosphere
        default:          return atmosphere
        }
    }

    var body: some View {
        ZStack {
            // Outer atmospheric corona — reacts to voice state
            Circle()
                .fill(glowColor.opacity(glowOpacity * 0.55))
                .frame(width: size * 1.85, height: size * 1.85)
                .blur(radius: 52)

            Circle()
                .fill(glowColor.opacity(glowOpacity * 0.28))
                .frame(width: size * 1.3, height: size * 1.3)
                .blur(radius: 24)

            // Earth sphere
            ZStack {
                // Ocean base — static, always fills the sphere
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                midOcean,
                                deepOcean,
                                Color.black.opacity(0.82)
                            ],
                            center: UnitPoint(x: 0.40, y: 0.36),
                            startRadius: 0,
                            endRadius: size * 0.56
                        )
                    )

                // Rotating continent layer — gradient blobs that bleed into each other
                ZStack {
                    // Old World: Africa + Eurasia merged into one broad green gradient
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [landBright.opacity(0.80), landDark.opacity(0.45), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: size * 0.28
                            )
                        )
                        .frame(width: size * 0.68, height: size * 0.68)
                        .offset(x: size * 0.10, y: -size * 0.06)
                        .blur(radius: 20)

                    // Americas: softer green mass on the left
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [landDark.opacity(0.72), landBright.opacity(0.32), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: size * 0.20
                            )
                        )
                        .frame(width: size * 0.48, height: size * 0.48)
                        .offset(x: -size * 0.20, y: size * 0.06)
                        .blur(radius: 16)

                    // Pacific / SE Asia: secondary green accent, right side
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [landBright.opacity(0.55), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: size * 0.14
                            )
                        )
                        .frame(width: size * 0.34, height: size * 0.34)
                        .offset(x: size * 0.22, y: size * 0.10)
                        .blur(radius: 13)
                }
                .rotationEffect(.degrees(rotationDeg))

                // Ice cap — North Pole: radial gradient, fades to transparent
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [iceWhite.opacity(0.52), iceWhite.opacity(0.18), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.16
                        )
                    )
                    .frame(width: size * 0.42, height: size * 0.42)
                    .offset(y: -size * 0.36)
                    .blur(radius: 16)

                // Ice cap — South Pole: radial gradient, fades to transparent
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [iceWhite.opacity(0.44), iceWhite.opacity(0.14), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.13
                        )
                    )
                    .frame(width: size * 0.36, height: size * 0.36)
                    .offset(y: size * 0.37)
                    .blur(radius: 14)

                // Specular highlight — top-left (fixed light source)
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.48), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.17
                        )
                    )
                    .frame(width: size * 0.36, height: size * 0.22)
                    .offset(x: -size * 0.10, y: -size * 0.14)

                // Atmosphere rim — thin blue-white edge glow
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                atmosphere.opacity(0.58),
                                atmosphere.opacity(0.18),
                                Color.clear,
                                atmosphere.opacity(0.28)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: max(size * 0.034, 2)
                    )
                    .blur(radius: 2)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .shadow(color: glowColor.opacity(0.45), radius: 26, x: 0, y: 0)
            .scaleEffect(breatheToggle ? 1.04 : 1.0)

            // Speaking ring — expands outward when AI is talking
            Circle()
                .strokeBorder(
                    atmosphere.opacity((1.0 - ringPhase) * 0.42),
                    lineWidth: 1.0
                )
                .frame(
                    width:  size * (1.0 + CGFloat(ringPhase) * 0.85),
                    height: size * (1.0 + CGFloat(ringPhase) * 0.85)
                )
                .opacity(voiceState == .speaking ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: voiceState == .speaking)
        }
        .onAppear {
            // Slow globe spin — 24s full rotation, set once, never interrupted
            withAnimation(.linear(duration: 24).repeatForever(autoreverses: false)) {
                rotationDeg = 360
            }
            // Breathing — 4.5s cycle, set once
            withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) {
                breatheToggle = true
            }
            applyVisuals(voiceState)
        }
        .onChange(of: voiceState) { _, newState in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                applyVisuals(newState)
            }
            if newState == .speaking {
                startRingLoop()
            } else {
                ringTask?.cancel()
                ringTask = nil
                withAnimation(.easeOut(duration: 0.4)) { ringPhase = 0 }
            }
        }
        .onDisappear {
            ringTask?.cancel()
            ringTask = nil
        }
    }

    private func applyVisuals(_ state: VoiceState) {
        switch state {
        case .idle:         glowOpacity = 0.32
        case .listening:    glowOpacity = 0.62
        case .thinking:     glowOpacity = 0.44
        case .speaking:     glowOpacity = 0.68
        case .reconnecting: glowOpacity = 0.22
        case .paused:       glowOpacity = 0.18
        case .error:        glowOpacity = 0.18
        }
    }

    private func startRingLoop() {
        ringTask?.cancel()
        ringTask = Task { @MainActor in
            while !Task.isCancelled {
                ringPhase = 0
                try? await Task.sleep(for: .milliseconds(40))
                guard !Task.isCancelled else { break }
                withAnimation(.easeOut(duration: 2.8)) { ringPhase = 1.0 }
                try? await Task.sleep(for: .seconds(3.0))
            }
        }
    }
}

// MARK: - 3. Pulse Ring Orb

struct PulseRingOrbView: View {
    let accentTheme: AccentTheme
    let voiceState: VoiceState
    let heartRate: Double?
    let size: CGFloat

    @State private var ringScales: [CGFloat] = [1.0, 1.0, 1.0, 1.0]
    @State private var ringOpacities: [Double] = [0.6, 0.45, 0.3, 0.15]

    private var pulseInterval: Double {
        guard let hr = heartRate, hr > 0 else { return 3.0 }
        return 60.0 / hr
    }

    private var activeColor: Color {
        voiceState == .listening ? .green : accentTheme.color
    }

    var body: some View {
        ZStack {
            ForEach(0..<4) { i in
                Circle()
                    .strokeBorder(
                        activeColor.opacity(ringOpacities[i]),
                        lineWidth: i == 0 ? 3 : 1.5
                    )
                    .frame(
                        width: size * (0.3 + CGFloat(i) * 0.2) * ringScales[i],
                        height: size * (0.3 + CGFloat(i) * 0.2) * ringScales[i]
                    )
            }

            Circle()
                .fill(activeColor)
                .frame(width: 12, height: 12)
                .shadow(color: activeColor.opacity(0.6), radius: 10)
        }
        .onAppear { animateRings() }
    }

    private func animateRings() {
        for i in 0..<4 {
            let delay = Double(i) * 0.15
            withAnimation(
                .easeInOut(duration: pulseInterval)
                .repeatForever(autoreverses: true)
                .delay(delay)
            ) {
                ringScales[i] = 1.15
                ringOpacities[i] = ringOpacities[i] * 0.5
            }
        }
    }
}
