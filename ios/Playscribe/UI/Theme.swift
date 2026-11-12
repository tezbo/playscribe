import SwiftUI

enum Brand {
    /// The product name. One constant, so a rename is one line.
    static let name = "Playscribe"
    static let trademarkNotice = "PlayStation, PS5, PlayStation Plus and the PlayStation Family Mark, and their logos, icons and branding, are trademarks of Sony Interactive Entertainment Inc. Playscribe is not affiliated with or endorsed by Sony Interactive Entertainment."
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
    /// Wishlist (Iris, 0.5.1): a clear yellow, lighter than the amber ember so the two never read as one.
    static let wishlist = Color(hex: "#F5C84B")
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
            // Never broken mid-word ("Reporte/d"): one line at its natural width; rows stack tags under the title at AX.
            .lineLimit(1).fixedSize()
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
    private static let utc: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = .gmt; return c }()
    /// Patch and release dates are facts about the patch, not the reader: the UTC calendar day, whatever the device's zone
    /// (Nadia, 7 Nov 2026; docs/decisions/release-date-timezone.md). The same patch reads the same on every phone, shared card and runner.
    var shortDay: String { formatted(Date.FormatStyle(locale: Self.dayFirst, timeZone: .gmt).day().month(.abbreviated).year()) }
    var dayMonth: String { formatted(Date.FormatStyle(locale: Self.dayFirst, timeZone: .gmt).day().month(.abbreviated)) }
    /// "16 Oct" this year, "16 Oct 2025" before (years counted in UTC too).
    var dayMonthOrYear: String { Self.utc.isDate(self, equalTo: .now, toGranularity: .year) ? dayMonth : shortDay }
    /// A moment on this device ("Checked 7 Nov, 11:20"): the device's own zone, not the patch rule above.
    var localDayMonth: String { formatted(Date.FormatStyle(locale: Self.dayFirst).day().month(.abbreviated)) }
    var localShortDay: String { formatted(Date.FormatStyle(locale: Self.dayFirst).day().month(.abbreviated).year()) }
    /// The UTC calendar, for anything counted in days against a printed patch date ("Out today", "3 days ago"), so a label never disagrees with it.
    static var utcCalendar: Calendar { utc }
    /// Whether `a` and `b` fall on the same UTC calendar day.
    static func sameUTCDay(_ a: Date, _ b: Date) -> Bool { utc.isDate(a, inSameDayAs: b) }
    /// Whether `a` and `b` fall in the same UTC calendar year.
    static func sameUTCYear(_ a: Date, _ b: Date) -> Bool { utc.isDate(a, equalTo: b, toGranularity: .year) }
    /// Whether this release day is today or in the next six UTC days: the "coming this week" window. A day-precision release
    /// date is a UTC day, so the window is counted in UTC days and never disagrees with the printed date (r060-utc-day-labels).
    func isInUTCWeek(from now: Date = .now) -> Bool {
        let start = Self.utc.startOfDay(for: now)
        return self >= start && self < start.addingTimeInterval(7 * 86400)
    }
}

extension String {
    /// "Deliverance II" with a no-break space before a trailing Roman numeral, so the numeral never wraps onto a line of its own
    /// (Open portrait showed "II ✓" alone under "Deliverance"; r060-nbsp-roman-numerals). Only a numeral up to XX after at least one
    /// other word; every other title is returned unchanged.
    var gluingTrailingNumeral: String {
        guard let space = lastIndex(of: " ") else { return self }
        let last = self[index(after: space)...]
        let numerals: Set<Substring> = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX"]
        guard numerals.contains(last), self[..<space].contains(where: { !$0.isWhitespace }) else { return self }
        return String(self[..<space]) + "\u{00A0}" + last
    }

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


/// QA (internal builds, launch with `-qaReduceTransparency YES`): every material is drawn solid, as under
/// Reduce Transparency, which the simulator cannot switch on (Iris, 0.5.0 accessibility pass).
private struct QASolidKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var qaSolid: Bool {
        get { self[QASolidKey.self] }
        set { self[QASolidKey.self] = newValue }
    }
}

/// Glass that becomes solid ink with a 1 pt vellum border under Reduce Transparency or Increase
/// Contrast (Iris, 0.5.0 accessibility pass).
private struct AdaptiveGlass<S: InsettableShape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.qaSolid) private var qaSolid
    var shape: S
    var interactive: Bool

    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased || qaSolid {
            content
                .background(Color.ink2, in: shape)
                .overlay(shape.strokeBorder(PlayscribeColor.vellum500, lineWidth: 1))
        } else {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        }
    }
}

extension View {
    func adaptiveGlass<S: InsettableShape>(in shape: S, interactive: Bool = false) -> some View {
        modifier(AdaptiveGlass(shape: shape, interactive: interactive))
    }
}
