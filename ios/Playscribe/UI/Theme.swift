import SwiftUI

enum Brand {
    /// The product name. One constant, so a rename is one line.
    static let name = "Playscribe"
    static let tagline = "Every update, a new chapter"
    static let trademarkNotice = "PlayStation, PS5 and the PlayStation Family Mark are trademarks of Sony Interactive Entertainment Inc. Playscribe is not affiliated with or endorsed by Sony Interactive Entertainment."
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let v = UInt64(s, radix: 16) ?? 0
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    // Brand v1 (brand/tokens.json): ink is the ground, vellum the pages, ember the accent.
    static let ink0 = PlayscribeColor.ink950
    static let ink1 = PlayscribeColor.ink900
    static let ink2 = PlayscribeColor.ink800
    static let ink3 = PlayscribeColor.ink700
    static let ink4 = PlayscribeColor.ink600
    static let ember = PlayscribeColor.vellum500
    static let ok = Color(hex: "#6fd3a0")
    static let simulated = Color(hex: "#c9a3ff")
    static let brand1 = PlayscribeColor.vellum300
    static let brand2 = PlayscribeColor.vellum100
    static let brand3 = PlayscribeColor.vellum500
    static let spark = PlayscribeColor.ember500
    static let watching = Color(hex: "#a99be0")
}

extension OwnershipStatus {
    /// GR-6: the status's own symbol.
    var symbol: String {
        switch self {
        case .owned: "gamecontroller"
        case .wishlist: "star"
        case .watching: "binoculars"
        }
    }

    var tint: Color {
        switch self {
        case .owned: .ok
        case .wishlist: PlayscribeColor.vellum500
        case .watching: .watching
        }
    }
}

/// A small capsule label. Text uses .caption2 so it never drops below 11 pt (G-7).
struct Tag: View {
    var text: String
    var tint: Color = .secondary
    var body: some View {
        Text(text)
            .font(PlayscribeFont.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.16), in: Capsule())
    }
}

struct StatusPill: View {
    var status: OwnershipStatus
    var body: some View { Tag(text: status.label, tint: status.tint) }
}

struct UnreadDot: View {
    var body: some View {
        Circle().fill(PlayscribeColor.accent).frame(width: 8, height: 8)
            .accessibilityLabel("Unread")
    }
}

extension View {
    /// Keeps hit areas at least 44 × 44 pt (G-7).
    func hitTarget() -> some View {
        frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }
}

extension Date {
    /// Playscribe writes dates day-first ("19 Nov 2026") in every locale, so copy reads the same
    /// everywhere and tests don't depend on the runner's region.
    private static let dayFirst = Locale(identifier: "en_GB")
    var shortDay: String { formatted(Date.FormatStyle(locale: Self.dayFirst).day().month(.abbreviated).year()) }
    var dayMonth: String { formatted(Date.FormatStyle(locale: Self.dayFirst).day().month(.abbreviated)) }
}

extension String {
    /// ISO day ("2026-09-03") to a Date at noon UTC.
    var isoDay: Date? {
        var c = DateComponents()
        let p = split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        c.year = p[0]; c.month = p[1]; c.day = p[2]; c.hour = 12
        c.timeZone = .gmt
        return Calendar(identifier: .gregorian).date(from: c)
    }
}
