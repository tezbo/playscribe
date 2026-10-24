import SwiftUI

enum Brand {
    /// The product name. One constant, so a rename is one line.
    static let name = "Playscribe"
    static let tagline = "Your PS5 games, in a book"
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let v = UInt64(s, radix: 16) ?? 0
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    static let ink0 = Color(hex: "#0b0d12")
    static let ink1 = Color(hex: "#11141b")
    static let ink2 = Color(hex: "#171b24")
    static let ink3 = Color(hex: "#1f2430")
    static let ink4 = Color(hex: "#2a3040")
    static let ember = Color(hex: "#e8b169")
    static let ok = Color(hex: "#6fd3a0")
    static let simulated = Color(hex: "#c9a3ff")
    static let brand1 = Color(hex: "#7fb2ff")
    static let brand2 = Color(hex: "#d6e5ff")
    static let brand3 = Color(hex: "#3d6fdc")
    static let spark = Color(hex: "#f2bd6b")
}

extension OwnershipStatus {
    var tint: Color {
        switch self {
        case .owned: .ok
        case .wishlist: .ember
        case .watching: .accentColor
        }
    }
}

/// A small capsule label. Text uses .caption2 so it never drops below 11 pt (G-7).
struct Tag: View {
    var text: String
    var tint: Color = .secondary
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

struct StatusPill: View {
    var status: OwnershipStatus
    var body: some View { Tag(text: status.label, tint: status.tint) }
}

struct UnreadDot: View {
    var body: some View {
        Circle().fill(Color.accentColor).frame(width: 8, height: 8)
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
    var shortDay: String { formatted(.dateTime.day().month(.abbreviated).year()) }
    var dayMonth: String { formatted(.dateTime.day().month(.abbreviated)) }
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
