import SwiftUI
import UIKit

/// Drop-in replacement for `AsyncImage` backed by `ImageStore` (memory + disk).
///
/// Shows `placeholder` until the image resolves, then crossfades it in. An
/// already-cached image is shown synchronously (no flicker while scrolling);
/// a miss falls back to the async memory → disk → network pipeline.
struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
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

        image = nil
        let loaded = await ImageStore.shared.image(for: url)
        // The cell may have been reused for a different url while we awaited.
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.35)) { image = loaded }
    }
}
