import SwiftUI

struct DebugLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var entries: [DebugLogger.Entry] = []

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if entries.isEmpty {
                    Text("No logs yet.\nTrigger an error and reopen.")
                        .font(RAAHTheme.Typography.body())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(entries) { entry in
                                    Text(entry.formatted)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(color(for: entry.tag))
                                        .textSelection(.enabled)
                                        .id(entry.id)
                                }
                            }
                            .padding(RAAHTheme.Spacing.md)
                        }
                        .onAppear {
                            if let last = entries.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Debug Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") {
                        DebugLogger.shared.clear()
                        entries = []
                        HapticEngine.light()
                    }
                    .foregroundStyle(.red)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(copied ? "Copied ✓" : "Copy All") {
                        UIPasteboard.general.string = DebugLogger.shared.fullLog
                        copied = true
                        HapticEngine.success()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                    }
                    .foregroundStyle(copied ? .green : .blue)
                }
            }
        }
        .onAppear { entries = DebugLogger.shared.entries }
        .preferredColorScheme(.dark)
    }

    private func color(for tag: String) -> Color {
        switch tag {
        case "Music":    return .pink
        case "Nav":      return .blue
        case "Calendar": return .purple
        case "Context":  return .green
        case "Places":   return .orange
        case "Safety":   return .red
        default:         return .white.opacity(0.7)
        }
    }
}
