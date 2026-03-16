import SwiftUI

struct FloatingTabBar: View {
    @Binding var selectedTab: AppTab
    let accentColor: Color

    @Namespace private var tabAnimation

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.rawValue) { tab in
                tabItem(tab)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
            Capsule()
                .fill(Color.white.opacity(0.04))
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.06),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        }
        .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 8)
        .shadow(color: accentColor.opacity(0.08), radius: 16, x: 0, y: 0)
        .padding(.horizontal, 72)
    }

    private func tabItem(_ tab: AppTab) -> some View {
        Button {
            withAnimation(RAAHTheme.Motion.snappy) {
                selectedTab = tab
            }
            HapticEngine.selection()
        } label: {
            ZStack {
                if selectedTab == tab {
                    Circle()
                        .fill(accentColor.opacity(0.18))
                        .frame(width: 42, height: 42)
                        .matchedGeometryEffect(id: "tab_bg", in: tabAnimation)
                }

                Image(systemName: tab.icon)
                    .font(.system(size: 19, weight: selectedTab == tab ? .semibold : .regular))
                    .foregroundStyle(selectedTab == tab ? accentColor : Color.white.opacity(0.38))
                    .scaleEffect(selectedTab == tab ? 1.08 : 1.0)
                    .animation(RAAHTheme.Motion.snappy, value: selectedTab == tab)
            }
            .frame(width: 54, height: 48)
        }
        .buttonStyle(.plain)
    }
}
