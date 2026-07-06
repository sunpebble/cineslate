import SwiftUI

enum AppTab: Hashable { case discover, mine }

enum BrowseTarget: Hashable {
    case genre(GenreCard)
    case studio(StudioCard)

    var title: String {
        switch self {
        case .genre(let g): return g.name
        case .studio(let s): return s.name
        }
    }
}

/// App-wide navigation + modal state.
@MainActor
final class Router: ObservableObject {
    @Published var tab: AppTab = .discover
    @Published var path = NavigationPath()
    @Published var showSettings = false
    @Published var showKeyEditor = false

    func open(_ ref: MediaRef) { path.append(ref) }
    func browse(_ target: BrowseTarget) { path.append(target) }
    func popToRoot() { path = NavigationPath() }

    func select(_ newTab: AppTab) {
        if tab == newTab { popToRoot() } else { tab = newTab }
    }
}
