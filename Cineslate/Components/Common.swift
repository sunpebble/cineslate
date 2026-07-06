import SwiftUI

/// "今日热门剧集 ›" style section header.
struct SectionHeader: View {
    let title: String
    var showsChevron: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 23, weight: .heavy))
                .foregroundStyle(RFX.text)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
    }
}

/// A simple full-bleed loading shimmer placeholder block.
struct LoadingBlock: View {
    var height: CGFloat
    var cornerRadius: CGFloat = 16
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(RFX.card)
            .frame(height: height)
            .redacted(reason: .placeholder)
    }
}
