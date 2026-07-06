import SwiftUI

struct DetailView: View {
    let ref: MediaRef

    @EnvironmentObject private var router: Router
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var plex: PlexStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var model: DetailViewModel
    @State private var playerContext: PlayerContext?

    init(ref: MediaRef) {
        self.ref = ref
        _model = StateObject(wrappedValue: DetailViewModel(ref: ref))
    }

    var body: some View {
        ZStack(alignment: .top) {
            RFX.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    sourceCard
                    actionChips
                    overviewBlock
                    similarSection
                    stillsSection
                    castSection
                    Color.clear.frame(height: 30)
                }
            }
            .rfxScroll()
            .ignoresSafeArea(edges: .top)
        }
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar { detailToolbar }
        .tint(.white)
        .task {
            await model.load()
            await model.loadPlexSource(plex)
        }
        .fullScreenCover(item: $playerContext) { context in
            PlayerView(context: context)
                .environmentObject(plex)
        }
    }

    /// Builds the player context from the matched Plex source + TMDB metadata.
    private func play(_ match: PlexMatch) {
        playerContext = PlayerContext(
            match: match,
            tmdbId: ref.id,
            imdbId: model.detail?.externalIds?.imdbId,
            title: model.detail?.displayTitle ?? match.serverName,
            year: model.detail?.year,
            mediaType: ref.type
        )
    }

    // MARK: Toolbar (system nav bar → Liquid Glass + interactive swipe-back)

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").fontWeight(.semibold)
            }
            .buttonStyle(.glass)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { if let snapshot = model.snapshot() { await library.toggle(snapshot, in: .watchLater) } }
            } label: {
                let saved = library.contains(ref: ref, in: .watchLater)
                Image(systemName: saved ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(saved ? RFX.accent : .white)
            }
            .buttonStyle(.glass)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.glass)
        }
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .bottom) {
            // Textless portrait poster fills the tall (full-width × 640) hero with
            // almost no crop AND carries no baked-in title, so the logo overlay
            // below is the only title shown.
            RemoteImage(path: model.detail?.heroPosterPath,
                        size: .original, seed: model.detail?.displayTitle ?? "\(ref.id)")
                .frame(height: 640)
                .clipped()

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.3), location: 0),
                    .init(color: .black.opacity(0.05), location: 0.3),
                    .init(color: RFX.bg, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )

            VStack(spacing: 0) {
                heroTitle

                if let detail = model.detail {
                    Text(detail.metaLine(type: ref.type))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xd8d8da))
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.6), radius: 8, y: 1)
                        .padding(.top, 18)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 18)
        }
        .frame(height: 640)
    }

    /// Title-art logo when TMDB has one (preferred), else the plain text title.
    @ViewBuilder private var heroTitle: some View {
        if let logo = model.detail?.titleLogoPath {
            CachedAsyncImage(url: tmdbImageURL(logo, .w500), contentMode: .fit) { Color.clear }
                .frame(height: 92)
                .frame(maxWidth: .infinity)
                .shadow(color: .black.opacity(0.55), radius: 14, y: 2)
                .padding(.horizontal, 24)
        } else {
            Text(model.detail?.displayTitle ?? "")
                .font(.system(size: 44, weight: .black))
                .kerning(2)
                .foregroundStyle(RFX.accent)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .shadow(color: .black.opacity(0.6), radius: 16, y: 2)
        }
    }

    // MARK: Source card — Plex-aware

    @ViewBuilder private var sourceCard: some View {
        Group {
            if let match = model.plexMatch {
                plexFoundCard(match)
            } else if model.isCheckingPlex {
                sourceLabel(icon: "magnifyingglass", text: String(localized: "正在 Plex 中查找…"), tint: RFX.text3, spin: true)
            } else if plex.isConnected {
                sourceLabel(icon: "nosign", text: String(localized: "Plex 中暂无此资源"), tint: Color(hex: 0xe6e6e8))
            } else {
                sourceLabel(icon: "nosign", text: String(localized: "没有找到可用资源"), tint: Color(hex: 0xe6e6e8))
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
    }

    private func sourceLabel(icon: String, text: String, tint: Color, spin: Bool = false) -> some View {
        HStack(spacing: 10) {
            if spin {
                ProgressView().controlSize(.small).tint(tint)
            } else {
                Image(systemName: icon).font(.system(size: 17)).opacity(0.7)
            }
            Text(text).font(.system(size: 18, weight: .bold))
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .glassRoundedRect(18)
    }

    private func plexFoundCard(_ match: PlexMatch) -> some View {
        VStack(spacing: 8) {
            Button {
                play(match)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "play.circle.fill").font(.system(size: 22))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "播放")).font(.system(size: 17, weight: .heavy))
                        Text(plexSubtitle(match)).font(.system(size: 12.5)).foregroundStyle(RFX.text2)
                    }
                    Spacer()
                    Image(systemName: "play.fill").font(.system(size: 15)).opacity(0.85)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .glassRoundedRect(18, interactive: true, tint: Color(hex: 0xe5a00d))
            }
            .buttonStyle(.plain)

            Button {
                openURL(match.deepLink)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.forward.app").font(.system(size: 12))
                    Text(String(localized: "用 Plex App 打开")).font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(RFX.text3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
    }

    private func plexSubtitle(_ match: PlexMatch) -> String {
        var parts = [match.serverName]
        if let resolution = match.resolution { parts.append(resolution) }
        return parts.joined(separator: " · ")
    }

    // MARK: Action chips (collect to library)

    private var actionChips: some View {
        HStack(spacing: 0) {
            chip(.favorite, icon: "heart", label: String(localized: "收藏"))
            Spacer(minLength: 8)
            chip(.watching, icon: "play.circle", label: String(localized: "正在观看"))
            Spacer(minLength: 8)
            chip(.history, icon: "checkmark.circle", label: String(localized: "看过"))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.top, 12)
    }

    private func chip(_ list: LibraryList, icon: String, label: String) -> some View {
        let active = library.contains(ref: ref, in: list)
        return Button {
            Task { if let s = model.snapshot() { await library.toggle(s, in: list) } }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: active ? icon + ".fill" : icon).font(.system(size: 13))
                Text(label).font(.system(size: 13, weight: .semibold))
            }
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(active ? .black : RFX.text2)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(active ? AnyShapeStyle(.white) : AnyShapeStyle(RFX.card), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Overview

    @ViewBuilder private var overviewBlock: some View {
        if let overview = model.detail?.overview, !overview.isEmpty {
            Text(overview)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(hex: 0xe2e2e4))
                .lineSpacing(5)
                .padding(22)
        } else if model.isLoading {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 4).fill(RFX.card).frame(height: 14)
                }
            }
            .padding(22)
            .redacted(reason: .placeholder)
        }
    }

    // MARK: Similar

    @ViewBuilder private var similarSection: some View {
        if let similar = model.detail?.similar?.results, !similar.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: String(localized: "更多类似"))
                ScrollView(.horizontal) {
                    HStack(spacing: 14) {
                        ForEach(similar) { media in
                            WideMediaCard(media: media, showsDescription: false) { router.open(media.ref) }
                        }
                    }
                    .padding(.horizontal, 22)
                }
                .rfxScroll()
                .padding(.bottom, 30)
            }
        }
    }

    // MARK: Stills

    @ViewBuilder private var stillsSection: some View {
        if let stills = model.detail?.images?.backdrops, !stills.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: String(localized: "剧照"))
                ScrollView(.horizontal) {
                    HStack(spacing: 14) {
                        ForEach(Array(stills.prefix(10).enumerated()), id: \.offset) { _, image in
                            RemoteImage(path: image.filePath, size: .w780, seed: image.filePath)
                                .frame(width: 300, height: 170)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .shadow(color: .black.opacity(0.4), radius: 8, y: 6)
                        }
                    }
                    .padding(.horizontal, 22)
                }
                .rfxScroll()
                .padding(.bottom, 30)
            }
        }
    }

    // MARK: Cast

    @ViewBuilder private var castSection: some View {
        if let cast = model.detail?.credits?.cast, !cast.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: String(localized: "演职人员"))
                ScrollView(.horizontal) {
                    HStack(spacing: 16) {
                        ForEach(cast.prefix(15)) { member in
                            VStack(spacing: 8) {
                                RemoteAvatar(path: member.profilePath, size: 88, seed: member.name)
                                Text(member.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(RFX.text)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .frame(width: 88)
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                }
                .rfxScroll()
            }
        }
    }
}
