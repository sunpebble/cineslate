import SwiftUI
import UIKit

/// Drop-in replacement for `AsyncImage` backed by `ImageStore` (memory + disk).
///
/// Shows `placeholder` until the image resolves, then crossfades it in. An
/// already-cached image is shown synchronously (no flicker while scrolling);
/// a miss falls back to the async memory → disk → network pipeline.
struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { image = nil; return }

        // Instant, lock-free memory hit — avoids a flicker on reused cells.
        if let cached = ImageStore.shared.memoryImage(for: url) {
            image = cached
            return
        }

        // Keep the current image (if any) while the new one resolves rather than
        // blanking to the placeholder up front — a disk hit (a few ms) then
        // crossfades in with no gradient flash. Only a genuine failure falls
        // back to the placeholder.
        let loaded = await ImageStore.shared.image(for: url)
        // The cell may have been reused for a different url while we awaited.
        guard !Task.isCancelled else { return }
        if let loaded {
            withAnimation(.easeOut(duration: 0.35)) { image = loaded }
        } else {
            image = nil
        }
    }
}
