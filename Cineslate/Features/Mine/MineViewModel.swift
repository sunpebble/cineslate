import SwiftUI

@MainActor
final class MineViewModel: ObservableObject {
    @Published var fallbackFeatured: TMDBMedia?

    func loadFallback() async {
        guard fallbackFeatured == nil else { return }
        fallbackFeatured = (try? await TMDBService.shared.trending(.tv))?.first
    }
}
