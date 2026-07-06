import SwiftUI

@main
struct CineslateApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var router = Router()
    @StateObject private var plex = PlexStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(router)
                .environmentObject(plex)
                .preferredColorScheme(.dark)
                .tint(RFX.accent)
        }
    }
}
