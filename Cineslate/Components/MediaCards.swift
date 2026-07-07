import SwiftUI

/// Hero card sized by its cell: the carousel hands each cell a fraction of the
/// screen, so this card fills whatever width it gets and keeps the design's
/// 361:520 portrait ratio — one big card + peek on iPhone, 2–3 across on iPad.
struct HeroCard: View {
    let media: TMDBMedia
    let onTap: () -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = w * 520.0 / 361.0
            Button(action: onTap) {
                ZStack(alignment: .bottom) {
                    // Portrait poster at .original: the card is 2:3-ish portrait, so a
                    // w780 *backdrop* (landscape, 439px tall) would be cropped to a
                    // sliver and upscaled ~3.5× — visibly blurry. The poster matches
                    // the card's aspect almost exactly and .original keeps it sharp
                    // at 3× on the full-width hero.
                    RemoteImage(path: media.posterPath ?? media.backdropPath, size: .original, seed: media.displayTitle)
                        .frame(width: w, height: h)

                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.15), location: 0),
                            .init(color: .clear, location: 0.35),
                            .init(color: .black.opacity(0.62), location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )

                    VStack(spacing: 0) {
                        Text(media.displayTitle)
                            .font(.system(size: 40, weight: .black))
                            .kerning(1)
                            .foregroundStyle(RFX.accentBright)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)
                            .shadow(color: .black.opacity(0.55), radius: 14, y: 2)
                            .padding(.bottom, 14)

                        Text(metaLine)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xe8e8ea))
                            .shadow(color: .black.opacity(0.7), radius: 8, y: 1)
                            .padding(.bottom, 16)

                        HStack(spacing: 10) {
                            Image(systemName: "play.fill").font(.system(size: 13))
                            Text(String(localized: "查看项目")).font(.system(size: 17, weight: .bold))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(.white, in: Capsule())
                        .shadow(color: .black.opacity(0.35), radius: 20, y: 6)
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 30)
                }
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .aspectRatio(361.0 / 520.0, contentMode: .fit)
    }

    private var metaLine: String {
        var parts: [String] = []
        if let year = media.year { parts.append(year) }
        if let vote = media.voteAverage, vote > 0 {
            parts.append("★ " + String(format: "%.1f", vote))
        }
        return parts.joined(separator: " · ")
    }
}

/// Numbered ranking card used by "今日热门剧集".
struct RankedCard: View {
    let rank: Int
    let media: TMDBMedia
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 6) {
                    Text("\(rank)")
                        .font(.system(size: 54, weight: .black))
                        .foregroundStyle(.white)
                    RemoteImage(path: media.posterPath ?? media.backdropPath, size: .w342, seed: media.displayTitle)
                        .frame(width: 79, height: 118)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 6)
                }
                Text(media.displayTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(RFX.text)
                    .lineLimit(1)
                    .padding(.top, 10)
                Text(metaLine)
                    .font(.system(size: 13))
                    .foregroundStyle(RFX.text4)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            .frame(width: 150, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private var metaLine: String {
        var parts: [String] = []
        if let year = media.year { parts.append(year) }
        parts.append(media.resolvedType == .tv ? String(localized: "剧集") : String(localized: "电影"))
        return parts.joined(separator: " · ")
    }
}

/// Wide landscape card used by "实时热门电视" and "更多类似".
struct WideMediaCard: View {
    let media: TMDBMedia
    var showsDescription: Bool = true
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                RemoteImage(path: media.backdropPath ?? media.posterPath, size: .w780, seed: media.displayTitle)
                    .frame(width: 268, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 6)

                if showsDescription {
                    Text(media.year ?? "")
                        .font(.system(size: 13))
                        .foregroundStyle(RFX.text4)
                        .padding(.top, 10)
                }
                Text(media.displayTitle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(RFX.text)
                    .lineLimit(1)
                    .padding(.top, showsDescription ? 2 : 10)

                if showsDescription, let overview = media.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 13))
                        .foregroundStyle(RFX.text4)
                        .lineLimit(2)
                        .lineSpacing(2)
                        .padding(.top, 4)
                }
            }
            .frame(width: 268, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}
