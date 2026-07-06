import SwiftUI

/// Deterministic gradient used as a poster/backdrop placeholder while the
/// real TMDB image loads (mirrors the source design's per-item gradients).
enum PlaceholderGradient {
    private static let palettes: [[UInt]] = [
        [0x6b5240, 0x4a3526, 0x2a1c12],
        [0x3a6e8c, 0x1e4a66, 0x0f2838],
        [0x56606a, 0x36404a, 0x1a2128],
        [0x7c8a96, 0x4a5660, 0x222a32],
        [0x4a3a3a, 0x2e2222, 0x160f0f],
        [0x2e5a6e, 0x102832, 0x0a1620],
        [0x8a2a2a, 0x3a0e0e, 0x200808],
        [0x3a4a6e, 0x1a2238, 0x0e1426],
        [0x4a8a3a, 0x1e4a18, 0x102a0c],
        [0x3a2a4a, 0x180e28, 0x0e0818],
    ]

    static func make(seed: Int) -> LinearGradient {
        let palette = palettes[abs(seed) % palettes.count]
        let colors = palette.map { Color(hex: $0) }
        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func seed(for string: String) -> Int {
        var hash = 5381
        for byte in string.utf8 { hash = ((hash << 5) &+ hash) &+ Int(byte) }
        return hash
    }
}
