import SwiftUI

/// A game's cover: bundled art, then the IGDB cover, then a title plate (E-4). The frame is set by
/// the caller and never changes while loading, so layout never shifts.
struct CoverView: View {
    var game: CatalogGame
    var cornerRadius: CGFloat = 8

    var body: some View {
        ZStack {
            plate
            if let asset = game.coverAsset {
                Image(asset).resizable().scaledToFill()
            } else if let url = game.coverURL {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                }
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

/// The Playscribe mark: an open book whose spine is the hinge, with a spark rising from it.
/// The two pages are separate shapes so layouts can split the mark across the fold.
nonisolated struct MarkPage: Shape {
    enum Side { case left, right }
    var side: Side

    func path(in rect: CGRect) -> Path {
        // Drawn on the prototype's 24 × 48 grid per page.
        let sx = rect.width / 24, sy = rect.height / 48
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let lx = side == .left ? x : x - 24
            return CGPoint(x: rect.minX + lx * sx, y: rect.minY + y * sy)
        }
        var path = Path()
        if side == .left {
            path.move(to: p(24, 13.5))
            path.addCurve(to: p(6.5, 11.2), control1: p(18.6, 10.4), control2: p(12.2, 9.6))
            path.addLine(to: p(5.4, 12.65))
            path.addLine(to: p(5.4, 35.75))
            path.addCurve(to: p(7.3, 37.17), control1: p(5.4, 36.75), control2: p(6.35, 37.45))
            path.addCurve(to: p(24, 39.37), control1: p(12.7, 35.67), control2: p(18.7, 36.37))
        } else {
            path.move(to: p(24, 13.5))
            path.addCurve(to: p(41.5, 11.2), control1: p(29.4, 10.4), control2: p(35.8, 9.6))
            path.addLine(to: p(42.6, 12.65))
            path.addLine(to: p(42.6, 35.75))
            path.addCurve(to: p(40.7, 37.17), control1: p(42.6, 36.75), control2: p(41.65, 37.45))
            path.addCurve(to: p(24, 39.37), control1: p(35.3, 35.67), control2: p(29.3, 36.37))
        }
        path.closeSubpath()
        return path
    }
}

nonisolated struct SparkShape: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 12
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * s, y: r.minY + y * s) }
        var path = Path()
        path.move(to: p(6, 0))
        path.addCurve(to: p(12, 6), control1: p(6.4, 3.2), control2: p(7.6, 4.6))
        path.addCurve(to: p(6, 12), control1: p(7.6, 7.4), control2: p(6.4, 8.8))
        path.addCurve(to: p(0, 6), control1: p(5.6, 8.8), control2: p(4.4, 7.4))
        path.addCurve(to: p(6, 0), control1: p(4.4, 4.6), control2: p(5.6, 3.2))
        path.closeSubpath()
        return path
    }
}

struct MarkPageView: View {
    var side: MarkPage.Side
    var height: CGFloat
    var body: some View {
        MarkPage(side: side)
            .fill(LinearGradient(colors: side == .left ? [.brand1, .brand3] : [.brand2, .brand1],
                                 startPoint: side == .left ? .topLeading : .topTrailing,
                                 endPoint: side == .left ? .bottomTrailing : .bottomLeading))
            .frame(width: height / 2, height: height)
    }
}

struct BrandMark: View {
    var size: CGFloat = 28
    var body: some View {
        HStack(spacing: 0) {
            MarkPageView(side: .left, height: size)
            MarkPageView(side: .right, height: size)
        }
        .overlay(alignment: .top) {
            SparkShape().fill(Color.spark).frame(width: size * 0.26, height: size * 0.26).offset(y: size * 0.02)
        }
        .accessibilityHidden(true)
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
