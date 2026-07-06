import SwiftUI

/// Root: Cineslate is private-by-design — no account, no gate. Launch straight
/// into the main shell.
struct RootView: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        ZStack {
            RFX.bgRoot.ignoresSafeArea()
            MainShell()
                .transition(.opacity)
        }
        .task { await debugHelpersIfNeeded() }
    }

    /// DEBUG-only convenience for UI verification. Launch env vars:
    ///   CINESLATE_SEED_LIBRARY=1                              → seed local watchlist
    ///   CINESLATE_START_TAB=mine                              → open Mine tab
    ///   CINESLATE_OPEN_DETAIL=tv:1399 (or movie:123)            → push a detail
    /// Compiled out of release builds.
    private func debugHelpersIfNeeded() async {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment

        if env["CINESLATE_SEED_LIBRARY"] == "1" {
            let movies = (try? await TMDBService.shared.trending(.movie)) ?? []
            let shows = (try? await TMDBService.shared.trending(.tv)) ?? []
            if let s = shows.first { await library.add(s, to: .watching) }
            if let m = movies.first { await library.add(m, to: .watchLater) }
            if shows.count > 1 { await library.add(shows[1], to: .history) }
        }

        if env["CINESLATE_START_TAB"] == "mine" { router.tab = .mine }

        if env["CINESLATE_OPEN_SETTINGS"] == "1" {
            try? await Task.sleep(nanoseconds: 900_000_000)
            router.showSettings = true
        }

        if env["CINESLATE_OPEN_BROWSE"] == "genre" {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            router.browse(.genre(GenreCard(name: String(localized: "剧情 Drama"), genreId: 18, colors: [0x3a4a6e, 0x1a2238])))
        }

        if let deepLink = env["CINESLATE_OPEN_DETAIL"] {
            let parts = deepLink.split(separator: ":")
            if parts.count == 2, let id = Int(parts[1]),
               let type = MediaType(rawValue: String(parts[0])) {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                router.open(MediaRef(id: id, type: type))
            }
        }
        #endif
    }
}
