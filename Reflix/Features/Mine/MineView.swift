import SwiftUI

struct MineView: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var library: LibraryStore
    @StateObject private var model = MineViewModel()

    @State private var segment: LibraryList = .watching

    private let segments: [LibraryList] = [.watching, .upcoming, .watchLater, .history]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleRow
                proBanner
                featured
                segmentPills
                rows
            }
            .padding(.bottom, 140)
        }
        .rfxScroll()
        .background(RFX.bg.ignoresSafeArea())
        .task {
            await library.loadAll()
            await model.loadFallback()
        }
        .refreshable { await library.loadAll() }
    }

    // MARK: Header

    private var titleRow: some View {
        HStack {
            HStack(spacing: 10) {
                Text("我的").font(.system(size: 32, weight: .black)).kerning(-0.5)
                Image(systemName: "nosign").font(.system(size: 18)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            HStack(spacing: 18) {
                Image(systemName: "plus").font(.system(size: 20))
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 18))
                Button { router.showSettings = true } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 19))
                }
            }
            .foregroundStyle(.white.opacity(0.95))
        }
        .foregroundStyle(RFX.text)
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private var proBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("🎉 升级到 Pro").font(.system(size: 17, weight: .heavy)).foregroundStyle(.white)
            Text("限时优惠，解锁超多精彩功能").font(.system(size: 14)).foregroundStyle(RFX.purple)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            LinearGradient(colors: [Color(hex: 0x26262a), Color(hex: 0x1b1b1f)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .padding(.horizontal, 22)
        .padding(.bottom, 18)
    }

    // MARK: Featured

    @ViewBuilder private var featured: some View {
        if let item = featuredItem {
            FeaturedCard(
                title: item.title,
                subtitle: item.subtitle,
                overview: item.overview,
                backdropPath: item.backdrop,
                seed: item.seed
            ) { router.open(item.ref) }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
    }

    // MARK: Segments

    private var segmentPills: some View {
        HStack(spacing: 8) {
            ForEach(segments) { seg in
                let active = segment == seg
                Button {
                    withAnimation(.snappy(duration: 0.25)) { segment = seg }
                } label: {
                    Text(seg.title)
                        .font(.system(size: 14, weight: active ? .bold : .semibold))
                        .foregroundStyle(active ? .black : RFX.text2)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(active ? AnyShapeStyle(Color.white) : AnyShapeStyle(RFX.card),
                                    in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 6)
    }

    // MARK: Rows

    @ViewBuilder private var rows: some View {
        let items = library.items(for: segment)
        if items.isEmpty {
            emptyState
        } else {
            ForEach(items) { item in
                LibraryRow(item: item, cta: cta(for: segment)) {
                    router.open(item.ref)
                } onRemove: {
                    Task { await library.remove(ref: item.ref, from: segment) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "popcorn").font(.system(size: 30)).foregroundStyle(RFX.text4)
            Text("「\(segment.title)」还是空的")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RFX.text3)
            Text("去发现页挑一部，加入这里")
                .font(.system(size: 13))
                .foregroundStyle(RFX.text4)
            Button("去发现") { router.select(.discover) }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(RFX.accent, in: Capsule())
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func cta(for list: LibraryList) -> String {
        switch list {
        case .watching: return "继续观看"
        case .upcoming: return "查看"
        case .watchLater: return "查看"
        case .history: return "重新观看"
        case .favorite: return "查看"
        }
    }

    // MARK: Featured selection

    private struct FeaturedData {
        let title: String
        let subtitle: String
        let overview: String
        let backdrop: String?
        let seed: String
        let ref: MediaRef
    }

    private var featuredItem: FeaturedData? {
        let order: [LibraryList] = [.watching, .upcoming, .watchLater, .favorite, .history]
        for list in order {
            if let first = library.items(for: list).first {
                return FeaturedData(
                    title: first.title ?? "",
                    subtitle: list.title,
                    overview: first.overview ?? "",
                    backdrop: first.backdropPath ?? first.posterPath,
                    seed: first.title ?? "rfx",
                    ref: first.ref
                )
            }
        }
        if let fb = model.fallbackFeatured {
            return FeaturedData(
                title: fb.displayTitle,
                subtitle: "为你推荐",
                overview: fb.overview ?? "",
                backdrop: fb.backdropPath ?? fb.posterPath,
                seed: fb.displayTitle,
                ref: fb.ref
            )
        }
        return nil
    }
}

// MARK: - Featured card

private struct FeaturedCard: View {
    let title: String
    let subtitle: String
    let overview: String
    let backdropPath: String?
    let seed: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(path: backdropPath, size: .w780, seed: seed)
                    .frame(maxWidth: .infinity, minHeight: 230, maxHeight: 230)

                LinearGradient(
                    stops: [.init(color: .black.opacity(0.1), location: 0.3),
                            .init(color: .black.opacity(0.78), location: 1)],
                    startPoint: .top, endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(subtitle.uppercased())
                        .font(.system(size: 12, weight: .semibold))
                        .kerning(2)
                        .foregroundStyle(RFX.accentSoft)
                    Text(title)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !overview.isEmpty {
                        Text(overview)
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: 0xf0f0f0))
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
                }
                .shadow(color: .black.opacity(0.6), radius: 6, y: 1)
                .padding(20)
            }
            .frame(height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Library row

private struct LibraryRow: View {
    let item: LibraryItem
    let cta: String
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 14) {
                RemoteImage(path: item.posterPath ?? item.backdropPath, size: .w342, seed: item.title ?? "")
                    .frame(width: 84, height: 118)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.title ?? "")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(RFX.text)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if let ep = episodeText {
                            Text(ep).font(.system(size: 13, weight: .semibold)).foregroundStyle(RFX.blue)
                        }
                    }
                    Text(metaText)
                        .font(.system(size: 13))
                        .foregroundStyle(RFX.text3)
                        .padding(.top, 4)
                    if let overview = item.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(size: 13))
                            .foregroundStyle(RFX.text3)
                            .lineLimit(2)
                            .lineSpacing(2)
                            .padding(.top, 8)
                    }
                    HStack(alignment: .bottom) {
                        Text(item.mediaType == "tv" ? "剧集" : "电影")
                            .font(.system(size: 12)).foregroundStyle(RFX.text5)
                        Spacer()
                        Text(cta)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .background(.white, in: Capsule())
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        }
        .buttonStyle(.plain)
        .overlay(Divider().background(RFX.hairline), alignment: .top)
        .contextMenu {
            Button(role: .destructive, action: onRemove) {
                Label("从列表移除", systemImage: "trash")
            }
        }
    }

    private var episodeText: String? {
        guard let s = item.season, let e = item.episode else { return nil }
        return String(format: "S%02dE%02d", s, e)
    }

    private var metaText: String {
        var parts: [String] = []
        parts.append(item.mediaType == "tv" ? "剧集" : "电影")
        if let runtime = item.runtimeMinutes, runtime > 0 { parts.append("\(runtime) 分钟") }
        return parts.joined(separator: " · ")
    }
}
