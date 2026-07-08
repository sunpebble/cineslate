import Foundation
import SwiftUI

/// The five library buckets surfaced on the "我的" tab.
enum LibraryList: String, CaseIterable, Identifiable {
    case watching       // 正在观看
    case upcoming       // 即将更新
    case watchLater     // 稍后观看
    case history        // 观看历史
    case favorite       // 收藏

    var id: String { rawValue }

    /// Stable on-disk discriminator for the bucket.
    var apiValue: String {
        switch self {
        case .watching: return "watching"
        case .upcoming: return "upcoming"
        case .watchLater: return "watch_later"
        case .history: return "history"
        case .favorite: return "favorite"
        }
    }

    var title: String {
        switch self {
        case .watching: return String(localized: "正在观看")
        case .upcoming: return String(localized: "即将更新")
        case .watchLater: return String(localized: "稍后观看")
        case .history: return String(localized: "观看历史")
        case .favorite: return String(localized: "收藏")
        }
    }
}

struct LibraryItem: Codable, Identifiable, Hashable {
    var tmdbId: Int
    var mediaType: String
    var listType: String
    var title: String?
    var posterPath: String?
    var backdropPath: String?
    var overview: String?
    var season: Int?
    var episode: Int?
    var progressMinutes: Int?
    var runtimeMinutes: Int?
    var addedAt: String?

    enum CodingKeys: String, CodingKey {
        case tmdbId = "tmdb_id"
        case mediaType = "media_type"
        case listType = "list_type"
        case title
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case overview
        case season
        case episode
        case progressMinutes = "progress_minutes"
        case runtimeMinutes = "runtime_minutes"
        case addedAt = "added_at"
    }

    /// Stable identity for `ForEach` — derived from the natural key, since there
    /// is no longer a server-issued row id.
    var id: String { "\(tmdbId)-\(mediaType)-\(listType)" }

    var ref: MediaRef {
        MediaRef(id: tmdbId, type: MediaType(rawValue: mediaType) ?? .movie)
    }
}

/// Local-only observable library repository. The full library is persisted to
/// `DiskCache` and rendered instantly on launch; writes update the UI immediately.
///
/// Supabase layer was removed to align with sunpebble's "private by design —
/// no account" promise. Upgrade path: if sync ever returns, re-introduce a
/// remote store behind this interface.
@MainActor
final class LibraryStore: ObservableObject {
    @Published var itemsByList: [String: [LibraryItem]] = [:]

    private let cacheKey = "library"

    init() {
        Task { await loadCachedSnapshot() }
    }

    func items(for list: LibraryList) -> [LibraryItem] {
        itemsByList[list.apiValue] ?? []
    }

    func contains(ref: MediaRef, in list: LibraryList) -> Bool {
        items(for: list).contains { $0.tmdbId == ref.id && $0.mediaType == ref.type.rawValue }
    }

    // MARK: Reads

    /// Renders the last persisted snapshot for an instant launch — only when
    /// nothing is loaded yet, so it never clobbers fresher in-memory state.
    private func loadCachedSnapshot() async {
        guard itemsByList.isEmpty,
              let entry = await DiskCache.shared.load(cacheKey, as: [String: [LibraryItem]].self)
        else { return }
        if itemsByList.isEmpty { itemsByList = entry.payload }
    }

    /// Reload from disk (pull-to-refresh / launch).
    func loadAll() async {
        await loadCachedSnapshot()
    }

    // MARK: Writes (local-only)

    func add(_ media: DetailLike, to list: LibraryList) async {
        insertOptimistic(optimisticItem(media, list: list), list: list)
        await persistSnapshot()
    }

    func remove(ref: MediaRef, from list: LibraryList) async {
        itemsByList[list.apiValue]?.removeAll {
            $0.tmdbId == ref.id && $0.mediaType == ref.type.rawValue
        }
        await persistSnapshot()
    }

    func toggle(_ media: DetailLike, in list: LibraryList) async {
        if contains(ref: media.ref, in: list) {
            await remove(ref: media.ref, from: list)
        } else {
            await add(media, to: list)
        }
    }

    // MARK: Helpers

    private func optimisticItem(_ media: DetailLike, list: LibraryList) -> LibraryItem {
        LibraryItem(
            tmdbId: media.tmdbId,
            mediaType: media.mediaType.rawValue,
            listType: list.apiValue,
            title: media.titleText,
            posterPath: media.poster,
            backdropPath: media.backdrop,
            overview: media.overviewText,
            season: nil,
            episode: nil,
            progressMinutes: nil,
            runtimeMinutes: media.runtime,
            addedAt: nil
        )
    }

    private func insertOptimistic(_ item: LibraryItem, list: LibraryList) {
        var arr = itemsByList[list.apiValue] ?? []
        guard !arr.contains(where: { $0.tmdbId == item.tmdbId && $0.mediaType == item.mediaType })
        else { return }
        arr.insert(item, at: 0)
        itemsByList[list.apiValue] = arr
    }

    private func persistSnapshot() async {
        await DiskCache.shared.save(cacheKey, itemsByList)
    }
}

/// Anything that can be saved to the library (a TMDB detail or a media row).
protocol DetailLike {
    var tmdbId: Int { get }
    var mediaType: MediaType { get }
    var titleText: String? { get }
    var poster: String? { get }
    var backdrop: String? { get }
    var overviewText: String? { get }
    var runtime: Int? { get }
}

extension DetailLike {
    var ref: MediaRef { MediaRef(id: tmdbId, type: mediaType) }
}

extension TMDBMedia: DetailLike {
    var tmdbId: Int { id }
    var mediaType: MediaType { resolvedType }
    var titleText: String? { displayTitle }
    var poster: String? { posterPath }
    var backdrop: String? { backdropPath }
    var overviewText: String? { overview }
    var runtime: Int? { nil }
}
