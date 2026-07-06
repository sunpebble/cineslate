import SwiftUI

/// Genre / studio browse grid reached from the Discover cards.
struct BrowseView: View {
    let target: BrowseTarget

    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss
    @State private var items: [TMDBMedia] = []
    @State private var isLoading = true

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items) { media in
                    Button { router.open(media.ref) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            RemoteImage(path: media.posterPath ?? media.backdropPath, size: .w500, seed: media.displayTitle)
                                .aspectRatio(2.0 / 3.0, contentMode: .fill)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            Text(media.displayTitle)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(RFX.text)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 40)

            if isLoading && items.isEmpty {
                ProgressView().tint(.white).padding(.top, 40)
            }
        }
        .rfxScroll()
        .background(RFX.bg.ignoresSafeArea())
        .navigationTitle(target.title)
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").fontWeight(.semibold)
                }
            }
        }
        .tint(.white)
        .task { await load() }
    }

    /// Cache-first: render the cached grid immediately, then revalidate from the
    /// network only when older than the soft TTL. Cached items survive failures.
    private func load() async {
        let key = "browse-\(target.cacheID)-\(TMDBService.contentLanguage)"
        if let entry = await DiskCache.shared.load(key, as: [TMDBMedia].self) {
            items = entry.payload
            isLoading = false
            if entry.isFresh(ttl: CacheTTL.browse) { return }
        } else {
            isLoading = true
        }
        do {
            let fresh: [TMDBMedia]
            switch target {
            case .genre(let g):
                fresh = try await TMDBService.shared.discover(type: .movie, genre: g.genreId)
            case .studio(let s):
                fresh = try await TMDBService.shared.discover(type: .tv, network: s.networkId)
            }
            items = fresh
            await DiskCache.shared.save(key, fresh)
        } catch {
            // Keep cached items (if any) on failure.
        }
        isLoading = false
    }
}

extension BrowseTarget {
    /// Stable cache key fragment per browse destination.
    var cacheID: String {
        switch self {
        case .genre(let g): return "genre-\(g.genreId)"
        case .studio(let s): return "studio-\(s.networkId)"
        }
    }
}
