import SwiftUI

@MainActor
final class DiscoverViewModel: ObservableObject {
    @Published var heroes: [TMDBMedia] = []
    @Published var rankedTV: [TMDBMedia] = []
    @Published var trendingTV: [TMDBMedia] = []
    @Published var people: [TMDBMedia] = []
    @Published var isLoading = false
    @Published var loadError: String?

    private var hasLoaded = false
    private static let cacheKey = "discover"

    /// Genre browse cards (fixed set, matching the source design).
    let genres: [GenreCard] = [
        GenreCard(name: "Drama", genreId: 18, colors: [0x3a4a6e, 0x1a2238]),
        GenreCard(name: "Comedy", genreId: 35, colors: [0x4a8a3a, 0x1e4a18]),
        GenreCard(name: "Thriller", genreId: 53, colors: [0x6e3a3a, 0x2a1414]),
        GenreCard(name: "Sci-Fi", genreId: 878, colors: [0x3a2a4a, 0x180e28]),
    ]

    /// Studio / network browse cards.
    let studios: [StudioCard] = [
        StudioCard(name: "NETFLIX", networkId: 213, colors: [0x2a2a32, 0x14141a]),
        StudioCard(name: "hulu", networkId: 453, colors: [0x3a5a4a, 0x162a20]),
        StudioCard(name: "tv+", networkId: 2552, colors: [0x4a4a52, 0x222228]),
        StudioCard(name: "HBO", networkId: 49, colors: [0x3a2a4a, 0x180e28]),
    ]

    /// Cache-first: render the last persisted snapshot immediately, then
    /// revalidate in the background only if it is older than the soft TTL.
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        if let entry = await DiskCache.shared.load(Self.cacheKey, as: DiscoverSnapshot.self) {
            apply(entry.payload)
            hasLoaded = true
            if !entry.isFresh(ttl: CacheTTL.discover) {
                await reload()
            }
        } else {
            await reload()
        }
    }

    /// Force a network refresh (pull-to-refresh + stale revalidation) and persist
    /// the snapshot. On failure the existing (cached) content is kept.
    func reload() async {
        isLoading = true
        loadError = nil
        do {
            async let trendingMovies = TMDBService.shared.trending(.movie, window: "day")
            async let trendingTVDay = TMDBService.shared.trending(.tv, window: "day")
            async let popularTV = TMDBService.shared.popularTV()
            async let trendingPeople = TMDBService.shared.trending(.person, window: "day")

            let movies = try await trendingMovies
            let tvDay = try await trendingTVDay
            let popular = try await popularTV
            let persons = try await trendingPeople

            heroes = Array(movies.prefix(5))
            rankedTV = Array(tvDay.prefix(5))
            trendingTV = Array(popular.prefix(8))
            people = Array(persons.prefix(10))
            hasLoaded = true
            await DiskCache.shared.save(Self.cacheKey, snapshot())
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? "加载失败，请检查网络或 API Key"
        }
        isLoading = false
    }

    private func snapshot() -> DiscoverSnapshot {
        DiscoverSnapshot(heroes: heroes, rankedTV: rankedTV, trendingTV: trendingTV, people: people)
    }

    private func apply(_ snapshot: DiscoverSnapshot) {
        heroes = snapshot.heroes
        rankedTV = snapshot.rankedTV
        trendingTV = snapshot.trendingTV
        people = snapshot.people
    }
}

/// Persisted snapshot of the discover feed, for instant / offline render.
struct DiscoverSnapshot: Codable {
    var heroes: [TMDBMedia]
    var rankedTV: [TMDBMedia]
    var trendingTV: [TMDBMedia]
    var people: [TMDBMedia]
}

struct GenreCard: Identifiable, Hashable {
    let name: String
    let genreId: Int
    let colors: [UInt]
    var id: Int { genreId }
    var gradient: LinearGradient {
        LinearGradient(colors: colors.map { Color(hex: $0) },
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct StudioCard: Identifiable, Hashable {
    let name: String
    let networkId: Int
    let colors: [UInt]
    var id: Int { networkId }
    var gradient: LinearGradient {
        LinearGradient(colors: colors.map { Color(hex: $0) },
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
