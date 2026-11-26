import SwiftUI

/// A game's cover: bundled art, then the IGDB cover, then a title plate (E-4). The frame is set by
/// the caller and never changes while loading, so layout never shifts.
struct CoverView: View {
    var game: CatalogGame
    var cornerRadius: CGFloat = 8
    /// Longest side, in pixels, the cover is decoded at. Tiles pass a small one; 800 keeps the full 528 x 748 cover.
    var maxPixel: Int = 800

    var body: some View {
        ZStack {
            plate
            if let asset = game.coverAsset {
                Image(asset).resizable().scaledToFill()
            } else if let url = game.coverURL {
                CachedCoverImage(url: url, maxPixel: maxPixel)
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .accessibilityElement()
        .accessibilityLabel("\(game.name) cover")
        .accessibilityAddTraits(.isImage)
    }

    private var plate: some View {
        let tones = (game.tones ?? ["#1b1d24", "#0b0d12"]).map(Color.init(hex:))
        return LinearGradient(colors: tones, startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                // One serif initial, 40% of the cover's height (never below 13 pt: a cover under 32 pt tall shows the plain
                // tinted plate). The title is always printed beside or below the cover, never inside the plate, so it can't
                // be cut mid-word (Iris, R-7).
                GeometryReader { geo in
                  if geo.size.height >= 32 {
                    Text(String(game.name.first(where: \.isLetter) ?? game.name.first ?? "?").uppercased())
                        // fixedSize: a sized custom font also scales with Dynamic Type, which overflowed the plate at AX5.
                        .font(.custom("Literata24pt-SemiBold", fixedSize: min(geo.size.height * 0.4, geo.size.width * 0.6)))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityHidden(true)
                  }
                }
            }
    }
}

/// Full-bleed artwork for stages and backdrops.
struct ArtView: View {
    var asset: String?
    var game: CatalogGame?
    var drift = false
    /// The front cover's per-game focal point; nil keeps the centre crop.
    var focus: CoverFocus? = nil
    /// Where in the frame the focal point is placed, 0 to 1 from the top (the cover puts it in the top half at large text).
    var focusTargetY: Double = 0.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                let tones = (game?.tones ?? ["#1b1d24", "#0b0d12"]).map(Color.init(hex:))
                LinearGradient(colors: tones, startPoint: .top, endPoint: .bottom)
                if let asset {
                    fill(Image(asset).resizable(), geo.size)
                } else if let url = game?.heroArtURL {
                    // Catalogue games have no bundled art: the official key art from the index.
                    AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                        if let image = phase.image {
                            fill(image.resizable(), geo.size)
                        } else if case .failure = phase {
                            defaultHeader(geo.size)
                        } else if let cover = game?.coverURL {
                            // While the key art loads (slow on a real connection; Iris on #596: Open portrait showed a flat grey
                            // band after View game), the cover the reader just tapped, already cached at the tile size, blurred and
                            // darkened as CoverHeader draws it. Never a blank band.
                            CachedCoverImage(url: cover, maxPixel: 480)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .blur(radius: 30).brightness(-0.35).clipped()
                        }
                    }
                } else {
                    // Never a blank header (Terry, sprint review): the brand's default art.
                    defaultHeader(geo.size)
                }
            }
            // Never larger than the space offered, whatever the image's own size (Terry: Tabletop
            // heroes for Enshrouded and Dawnwalker were far too big).
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .clipped()
        .accessibilityHidden(true)
        // bug-064: wide art under the status bar turns the bar light (light mode only) and carries a scrim there.
        .statusBarArt()
        .onAppear {
            guard drift, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) { phase = true }
        }
    }

    /// Fills the offered size exactly: the image is an overlay of a fixed frame, so its own size
    /// can never grow the layout. G-9: slow drift only when motion is allowed.
    private func fill(_ image: Image, _ size: CGSize) -> some View {
        Color.clear
            .frame(width: size.width, height: size.height)
            .overlay {
                if let focus {
                    // The focal point goes to (centre, focusTargetY), clamped so the image always covers the frame.
                    let natural = asset.flatMap { UIImage(named: $0)?.size } ?? CGSize(width: 1920, height: 1080)
                    let r = FocalCrop.place(image: natural, in: size, focus: focus, targetY: focusTargetY)
                    Color.clear.overlay(alignment: .topLeading) {
                        image.frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                    }
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(drift && !reduceMotion ? (phase ? 1.06 : 1.0) : 1.0)
                } else {
                    image.scaledToFill()
                        .scaleEffect(drift && !reduceMotion ? (phase ? 1.06 : 1.0) : 1.0)
                }
            }
            .clipped()
    }

    /// brand/hero default headers: 16:9 for wide spaces, 9:16 for tall ones.
    private func defaultHeader(_ size: CGSize) -> some View {
        Image(size.width >= size.height ? "default-header-wide" : "default-header-tall")
            .resizable().scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
    }
}

/// The Playscribe mark, Warm refresh (Terry picked 13 Nov; kit in gamebook/brand/identity/final, mark.svg and mark-rest.svg):
/// an open book whose spine is the hinge, a ribbon bookmark, and an ember spark above it. Drawn on the kit's 64-unit grid.
/// The two pages are separate shapes so layouts can split the mark across the fold (the splash in Book).
nonisolated enum MarkGrid {
    static func point(_ x: CGFloat, _ y: CGFloat, in r: CGRect, origin: CGPoint = .zero, unit: CGSize = CGSize(width: 64, height: 64)) -> CGPoint {
        CGPoint(x: r.minX + (x - origin.x) * r.width / unit.width, y: r.minY + (y - origin.y) * r.height / unit.height)
    }
    /// Each page's box on the grid: x 7.6 to 31.2 (left) or 32.8 to 56.4 (right), y 19.4 to 56.3.
    static let pageBox = CGSize(width: 23.6, height: 36.9)
    static let pageTop: CGFloat = 19.4
}

nonisolated struct MarkPage: Shape {
    enum Side { case left, right }
    var side: Side

    func path(in rect: CGRect) -> Path {
        // mark.svg: M31.2 25C25.2 20.6 16.8 19.4 9.4 21.3Q7.6 21.8 7.6 23.7V50.4Q7.6 52.9 10 52.4C17.2 50.8 25 51.8 31.2 56.3Z,
        // and its mirror (x -> 64 - x) for the right page. Drawn into the page's own box.
        let ox: CGFloat = side == .left ? 7.6 : 32.8
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let gx = side == .left ? x : 64 - x
            return MarkGrid.point(gx, y, in: rect, origin: CGPoint(x: ox, y: MarkGrid.pageTop), unit: MarkGrid.pageBox)
        }
        var path = Path()
        path.move(to: p(31.2, 25))
        path.addCurve(to: p(9.4, 21.3), control1: p(25.2, 20.6), control2: p(16.8, 19.4))
        path.addQuadCurve(to: p(7.6, 23.7), control: p(7.6, 21.8))
        path.addLine(to: p(7.6, 50.4))
        path.addQuadCurve(to: p(10, 52.4), control: p(7.6, 52.9))
        path.addCurve(to: p(31.2, 56.3), control1: p(17.2, 50.8), control2: p(25, 51.8))
        path.closeSubpath()
        return path
    }
}

/// A four-point spark (mark.svg: the large one centred at 32, 12.5, radius 9.5; the small one at 47, 8, radius 3.6).
nonisolated struct SparkShape: Shape {
    func path(in r: CGRect) -> Path {
        // Normalised from the kit's large spark: points at the box edges, waists pulled in by 0.3 of the radius.
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var path = Path()
        path.move(to: p(0.5, 0))
        path.addCurve(to: p(1, 0.5), control1: p(0.55, 0.3), control2: p(0.7, 0.45))
        path.addCurve(to: p(0.5, 1), control1: p(0.7, 0.55), control2: p(0.55, 0.7))
        path.addCurve(to: p(0, 0.5), control1: p(0.45, 0.7), control2: p(0.3, 0.55))
        path.addCurve(to: p(0.5, 0), control1: p(0.3, 0.45), control2: p(0.45, 0.3))
        path.closeSubpath()
        return path
    }
}

/// The ribbon bookmark hanging from the right page (mark.svg: M36.5 52.2L42.5 52.8V62L39.5 59.4L36.5 62Z).
nonisolated struct MarkRibbon: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { MarkGrid.point(x, y, in: rect) }
        var path = Path()
        path.move(to: p(36.5, 52.2))
        path.addLine(to: p(42.5, 52.8))
        path.addLine(to: p(42.5, 62))
        path.addLine(to: p(39.5, 59.4))
        path.addLine(to: p(36.5, 62))
        path.closeSubpath()
        return path
    }
}

struct MarkPageView: View {
    var side: MarkPage.Side
    var height: CGFloat
    /// mark-on-light.svg: darker pages, so the cream ones do not vanish on vellum.
    var onLight = false
    var body: some View {
        MarkPage(side: side)
            .fill(LinearGradient(colors: side == .left ? [Color(hex: onLight ? "#E6D8BC" : "#EBDDC1"), Color(hex: "#CDB68D")]
                                                       : [Color(hex: onLight ? "#EFE3C8" : "#FBF4E6"), Color(hex: onLight ? "#DCCBA5" : "#EBDDC1")],
                                 startPoint: side == .left ? .topLeading : .topTrailing,
                                 endPoint: side == .left ? .bottomTrailing : .bottomLeading))
            .overlay { if side == .left { lines([(31.6, 14.6), (36.6, 14.6), (41.6, 10.2)], x: 12.4) } else { lines([(31.6, 14.6), (36.6, 11)], x: 37) } }
            .frame(width: height * MarkGrid.pageBox.width / MarkGrid.pageBox.height, height: height)
    }

    /// The text lines on each page: 2.3-unit rules in ink at 28%.
    private func lines(_ rows: [(CGFloat, CGFloat)], x: CGFloat) -> some View {
        GeometryReader { g in
            let ox: CGFloat = side == .left ? 7.6 : 32.8
            let k = g.size.height / MarkGrid.pageBox.height
            ForEach(rows.indices, id: \.self) { i in
                Capsule().fill(Color(hex: "#0F0E14").opacity(0.28))
                    .frame(width: rows[i].1 * k, height: 2.3 * k)
                    .position(x: (x - ox + rows[i].1 / 2) * k, y: (rows[i].0 - MarkGrid.pageTop + 1.15) * k)
            }
        }
    }
}

/// The mark's two states (README, Behaviour): `lit`, the spark and ribbon glow ember with a halo, when there is an unread
/// update; at rest (mark-rest.svg) they are dim vellum #A8916A with no halo, when caught up. Static either way, so Reduce
/// Motion has nothing to stop: no flicker.
struct BrandMark: View {
    var size: CGFloat = 28
    var lit = true
    /// On a vellum ground (the light-mode splash): the mark-on-light.svg page tones.
    var onLight = false

    static let restInk = Color(hex: "#A8916A")
    /// Lit while any game in the library has an unread update; at rest when caught up.
    static func isLit(totalUnread: Int) -> Bool { totalUnread > 0 }
    static let emberSpark = LinearGradient(colors: [Color(hex: "#FFC86A"), Color(hex: "#F2813A")], startPoint: .top, endPoint: .bottom)

    var body: some View {
        let u = size / 64
        ZStack(alignment: .topLeading) {
            if lit {
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: "#FFB04F").opacity(0.55), Color(hex: "#FFB04F").opacity(0)],
                                         center: .center, startRadius: 0, endRadius: 15 * u))
                    .frame(width: 30 * u, height: 30 * u)
                    .offset(x: 17 * u, y: -2.5 * u)
            }
            HStack(spacing: 1.6 * u) {
                MarkPageView(side: .left, height: MarkGrid.pageBox.height * u, onLight: onLight)
                MarkPageView(side: .right, height: MarkGrid.pageBox.height * u, onLight: onLight)
            }
            .offset(x: 7.6 * u, y: MarkGrid.pageTop * u)
            MarkRibbon().fill(lit ? AnyShapeStyle(Self.emberSpark) : AnyShapeStyle(Self.restInk))
            spark(at: CGPoint(x: 32, y: 12.5), radius: 9.5, u: u)
            spark(at: CGPoint(x: 47, y: 8), radius: 3.6, u: u)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func spark(at c: CGPoint, radius: CGFloat, u: CGFloat) -> some View {
        SparkShape()
            .fill(lit ? AnyShapeStyle(Self.emberSpark) : AnyShapeStyle(Self.restInk))
            .frame(width: radius * 2 * u, height: radius * 2 * u)
            .offset(x: (c.x - radius) * u, y: (c.y - radius) * u)
    }
}

struct Wordmark: View {
    var body: some View {
        HStack(spacing: 6) {
            BrandMark(size: 22)
            Text(Brand.name).font(PlayscribeFont.subheadline.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Brand.name)
    }
}

/// A per-game focal point on cover art (Iris, #467): `x`, `y` from 0 (left, top) to 1, and `scale`, a zoom of 1 or more
/// beyond the fill (absent = 1).
struct CoverFocus: Codable, Hashable {
    var x: Double
    var y: Double
    var scale: Double?
}

enum FocalCrop {
    /// Where the image is drawn (in the frame's coordinates) so that it fills the frame, zoomed by `focus.scale`, with the focal
    /// point as near as it can get to the frame's horizontal centre and `targetY` down. Clamped: the image always covers the
    /// whole frame, so the focal point never pushes an edge into view.
    static func place(image: CGSize, in frame: CGSize, focus: CoverFocus, targetY: Double = 0.5) -> CGRect {
        guard image.width > 0, image.height > 0, frame.width > 0, frame.height > 0 else { return CGRect(origin: .zero, size: frame) }
        let fill = max(frame.width / image.width, frame.height / image.height) * max(1, focus.scale ?? 1)
        let w = image.width * fill, h = image.height * fill
        let fx = min(max(focus.x, 0), 1), fy = min(max(focus.y, 0), 1), ty = min(max(targetY, 0), 1)
        let x = min(0, max(frame.width - w, frame.width / 2 - fx * w))
        let y = min(0, max(frame.height - h, frame.height * ty - fy * h))
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
