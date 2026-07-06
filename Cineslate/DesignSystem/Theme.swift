import SwiftUI

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

/// Cineslate design tokens, lifted from the source design.
enum RFX {
    // Surfaces
    static let bg = Color(hex: 0x0c0c0d)
    static let bgRoot = Color.black
    static let card = Color(hex: 0x1e1e20)
    static let cardAlt = Color(hex: 0x2c2c2e)
    static let sheet = Color(hex: 0x1c1c1e)

    // Brand
    static let accent = Color(hex: 0xe8622a)
    static let accentBright = Color(hex: 0xf06a2e)
    static let accentSoft = Color(hex: 0xf0b89a)
    static let green = Color(hex: 0x34c759)
    static let blue = Color(hex: 0x4a8fe0)
    static let purple = Color(hex: 0x9a7ad8)

    // Text
    static let text = Color.white
    static let text2 = Color(hex: 0xc8c8cc)
    static let text3 = Color(hex: 0x9a9aa0)
    static let text4 = Color(hex: 0x7d7d82)
    static let text5 = Color(hex: 0x5a5a5e)

    static let hairline = Color.white.opacity(0.06)
}

extension View {
    /// Hides the scroll indicators the way the source design does.
    func rfxScroll() -> some View {
        self.scrollIndicators(.hidden)
    }
}
