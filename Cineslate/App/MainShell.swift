import SwiftUI

/// Hosts the Discover / Mine tabs, the navigation stack for detail + browse,
/// and the floating liquid-glass tab bar.
struct MainShell: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        NavigationStack(path: $router.path) {
            ZStack(alignment: .bottom) {
                RFX.bg.ignoresSafeArea()

                Group {
                    switch router.tab {
                    case .discover: DiscoverView()
                    case .mine: MineView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                TabBarView()
                    .padding(.bottom, 18)
            }
            .navigationDestination(for: MediaRef.self) { ref in
                DetailView(ref: ref)
            }
            .navigationDestination(for: BrowseTarget.self) { target in
                BrowseView(target: target)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(.white)
        .task { await library.loadAll() }
        .sheet(isPresented: $router.showSettings) {
            SettingsView()
        }
    }
}

/// Floating Liquid Glass tab bar (发现 / 我的).
struct TabBarView: View {
    @EnvironmentObject private var router: Router

    var body: some View {
        HStack(spacing: 4) {
            pill(.discover, systemImage: "sparkles", label: String(localized: "发现"))
            pill(.mine, systemImage: "play.tv.fill", label: String(localized: "我的"))
        }
        .padding(7)
        .glassCapsule()
        .overlay(
            Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        )
        // Absorb taps across the whole capsule so they don't fall through to
        // the scrolling cards behind the floating bar.
        .contentShape(Capsule())
        .onTapGesture { }
        .shadow(color: .black.opacity(0.45), radius: 16, y: 10)
    }

    private func pill(_ tab: AppTab, systemImage: String, label: String) -> some View {
        let active = router.tab == tab
        return Button {
            withAnimation(.snappy(duration: 0.3)) { router.select(tab) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage).font(.system(size: 15))
                Text(label).font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(active ? Color.black : Color(hex: 0xe6e6e8))
            .padding(.vertical, 13)
            .padding(.horizontal, 26)
            .background {
                if active {
                    Capsule().fill(Color.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
