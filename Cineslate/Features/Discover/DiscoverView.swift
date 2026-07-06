import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var router: Router
    @StateObject private var model = DiscoverViewModel()
    @State private var heroID: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleRow

                if let error = model.loadError, model.heroes.isEmpty {
                    errorState(error)
                } else {
                    heroCarousel
                    pageDots
                    rankedSection
                    trendingTVSection
                    genreSection
                    studioSection
                    peopleSection
                }
            }
            .padding(.bottom, 130)
        }
        .rfxScroll()
        .background(RFX.bg.ignoresSafeArea())
        .task { await model.loadIfNeeded() }
        .refreshable { await model.reload() }
    }

    // MARK: Header

    private var titleRow: some View {
        HStack {
            Text(String(localized: "发现"))
                .font(.system(size: 32, weight: .black))
                .kerning(-0.5)
            Spacer()
            HStack(spacing: 20) {
                Button { router.showSettings = true } label: {
                    Image(systemName: "sparkles").font(.system(size: 20))
                }
                Image(systemName: "magnifyingglass").font(.system(size: 20))
            }
            .foregroundStyle(.white.opacity(0.95))
        }
        .foregroundStyle(RFX.text)
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    // MARK: Hero carousel

    private var heroCarousel: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                ForEach(model.heroes) { hero in
                    HeroCard(media: hero) { router.open(hero.ref) }
                }
                if model.heroes.isEmpty {
                    ForEach(0..<2, id: \.self) { _ in
                        LoadingBlock(height: 520, cornerRadius: 26).frame(width: 361)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $heroID)
        .rfxScroll()
    }

    private var currentHeroIndex: Int {
        guard let heroID,
              let idx = model.heroes.firstIndex(where: { $0.id == heroID }) else { return 0 }
        return idx
    }

    private var pageDots: some View {
        let count = model.heroes.isEmpty ? 5 : model.heroes.count
        return HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == currentHeroIndex ? Color.white : Color.white.opacity(0.3))
                    .frame(width: i == currentHeroIndex ? 18 : 5, height: 5)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 26)
        .animation(.snappy, value: currentHeroIndex)
    }

    // MARK: Ranked TV

    private var rankedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: String(localized: "今日热门剧集"), showsChevron: true)
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(Array(model.rankedTV.enumerated()), id: \.element.id) { index, media in
                        RankedCard(rank: index + 1, media: media) { router.open(media.ref) }
                    }
                }
                .padding(.horizontal, 22)
            }
            .rfxScroll()
            .padding(.bottom, 32)
        }
    }

    // MARK: Trending TV

    private var trendingTVSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: String(localized: "实时热门电视"))
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(model.trendingTV) { media in
                        WideMediaCard(media: media) { router.open(media.ref) }
                    }
                }
                .padding(.horizontal, 22)
            }
            .rfxScroll()
            .padding(.bottom, 32)
        }
    }

    // MARK: Genres

    private var genreSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: String(localized: "按分类浏览"))
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(model.genres) { genre in
                        Button { router.browse(.genre(genre)) } label: {
                            ZStack(alignment: .bottomLeading) {
                                genre.gradient
                                if let backdrop = model.genreBackdrops[genre.genreId] {
                                    RemoteImage(path: backdrop, size: .w780, seed: genre.name)
                                    // Darken the lower half so the white title stays
                                    // legible over an arbitrary backdrop.
                                    LinearGradient(colors: [.clear, .black.opacity(0.55)],
                                                   startPoint: .center, endPoint: .bottom)
                                }
                                Text(genre.name)
                                    .font(.system(size: 28, weight: .black))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                                    .padding(.leading, 20)
                                    .padding(.bottom, 16)
                            }
                            .frame(width: 268, height: 118)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
            }
            .rfxScroll()
            .padding(.bottom, 32)
        }
    }

    // MARK: Studios

    private var studioSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: String(localized: "按工作室浏览"))
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(model.studios) { studio in
                        Button { router.browse(.studio(studio)) } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    studio.gradient
                                    if let logo = model.studioLogos[studio.networkId] {
                                        // Logos are transparent PNGs — sit them on the
                                        // gradient, fit + inset so the wordmark is whole.
                                        CachedAsyncImage(url: tmdbImageURL(logo, .w342),
                                                         contentMode: .fit) { Color.clear }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 26)
                                    }
                                }
                                .frame(width: 118, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                Text(studio.name)
                                    .font(.system(size: 16, weight: .heavy))
                                    .kerning(0.5)
                                    .foregroundStyle(Color(hex: 0xe9e9ec))
                                    .frame(width: 118, height: 46)
                                    .background(RFX.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
            }
            .rfxScroll()
            .padding(.bottom, 32)
        }
    }

    // MARK: People

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: String(localized: "今日热门人物"))
            ScrollView(.horizontal) {
                HStack(spacing: 18) {
                    ForEach(model.people) { person in
                        VStack(spacing: 10) {
                            RemoteAvatar(path: person.profilePath, size: 104, seed: person.displayTitle)
                            Text(person.displayTitle)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(RFX.text)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(width: 104)
                        }
                    }
                }
                .padding(.horizontal, 22)
            }
            .rfxScroll()
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 34))
                .foregroundStyle(RFX.accent)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(RFX.text3)
                .multilineTextAlignment(.center)
            Button(String(localized: "重试")) { Task { await model.reload() } }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22).padding(.vertical, 11)
                .background(RFX.accent, in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
        .padding(.horizontal, 40)
    }
}
