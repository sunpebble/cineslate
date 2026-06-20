import SwiftUI

@MainActor
final class DetailViewModel: ObservableObject {
    @Published var detail: TMDBDetail?
    @Published var isLoading = true
    @Published var error: String?

    @Published var plexMatch: PlexMatch?
    @Published var isCheckingPlex = false
    private var plexChecked = false

    let ref: MediaRef
    init(ref: MediaRef) { self.ref = ref }

    /// Cache-first: show the cached detail immediately, then revalidate from the
    /// network only if it is older than the soft TTL. On a network failure the
    /// cached detail is kept (no error shown).
    func load() async {
        let key = Self.cacheKey(ref)
        if let entry = await DiskCache.shared.load(key, as: TMDBDetail.self) {
            detail = entry.payload
            isLoading = false
            if entry.isFresh(ttl: CacheTTL.detail) { return }
            await refresh(key: key)
        } else {
            isLoading = true
            await refresh(key: key)
            isLoading = false
        }
    }

    private func refresh(key: String) async {
        do {
            let fresh = try await TMDBService.shared.detail(ref)
            detail = fresh
            error = nil
            await DiskCache.shared.save(key, fresh)
        } catch {
            // Keep cached content if we have it; only surface an error on a cold miss.
            if detail == nil {
                self.error = (error as? LocalizedError)?.errorDescription ?? "加载详情失败"
            }
        }
    }

    /// Looks the title up in the user's connected Plex libraries (once).
    func loadPlexSource(_ store: PlexStore) async {
        guard store.isConnected, let detail, !plexChecked else { return }
        plexChecked = true
        isCheckingPlex = true
        plexMatch = await store.findSource(ref: ref, title: detail.displayTitle, year: detail.year)
        isCheckingPlex = false
    }

    /// A snapshot that can be persisted to the user's library.
    func snapshot() -> MediaSnapshot? {
        guard let detail else { return nil }
        return MediaSnapshot(
            tmdbId: detail.id,
            mediaType: ref.type,
            titleText: detail.displayTitle,
            poster: detail.posterPath,
            backdrop: detail.backdropPath,
            overviewText: detail.overview,
            runtime: detail.runtimeMinutes
        )
    }

    // v2: detail payload now carries images.posters / images.logos — bumping the
    // key forces a one-time refetch so pre-existing caches don't hide them.
    static func cacheKey(_ ref: MediaRef) -> String { "detail-v2-\(ref.type.rawValue)-\(ref.id)" }
}

/// Concrete `DetailLike` used when saving a detail page to the library.
struct MediaSnapshot: DetailLike {
    let tmdbId: Int
    let mediaType: MediaType
    let titleText: String?
    let poster: String?
    let backdrop: String?
    let overviewText: String?
    let runtime: Int?
}
