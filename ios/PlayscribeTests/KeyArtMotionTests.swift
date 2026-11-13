import CoreGraphics
import Foundation
import Testing
@testable import Playscribe

/// s-07-keyart-motion (Iris's spec, 13 Nov): the path's clamps, the seamless ping-pong and the speed cap, without a simulator.
@MainActor
struct KeyArtMotionTests {
    // Closed portrait and landscape covers, std and AX5 (target and lowest focal point).
    private let cases: [(size: CGSize, focal: CGPoint, targetY: Double, maxY: Double)] = [
        (CGSize(width: 382, height: 466), CGPoint(x: 260, y: 233), 0.5, 1),
        (CGSize(width: 382, height: 466), CGPoint(x: 191, y: 180), 0.25, 0.5),
        (CGSize(width: 382, height: 466), CGPoint(x: 20, y: 440), 0.25, 0.5),     // a crop that left the focal point low and to one side
        (CGSize(width: 466, height: 382), CGPoint(x: 400, y: 100), 0.5, 1),
        (CGSize(width: 466, height: 382), CGPoint(x: 233, y: 95), 0.25, 0.5),
    ]

    private func path(_ c: (size: CGSize, focal: CGPoint, targetY: Double, maxY: Double)) -> KeyArtPath {
        KeyArtPath.make(size: c.size, focal: c.focal, target: CGPoint(x: c.size.width / 2, y: c.size.height * c.targetY),
                        maxFocalY: c.size.height * c.maxY)
    }

    private var times: [Double] { stride(from: 0.0, through: 48, by: 0.25).map { $0 } }

    @Test func loopIsSeamless() {
        #expect(KeyArtPath.ease(0) == 0)
        #expect(abs(KeyArtPath.ease(48)) < 1e-9)
        #expect(abs(KeyArtPath.ease(24) - 1) < 1e-9)
        // Velocity zero at both turns: the change over a 30 fps frame at the turns is tiny next to mid-leg.
        let atTurn = abs(KeyArtPath.ease(1.0 / 30) - KeyArtPath.ease(0))
        let midLeg = abs(KeyArtPath.ease(12 + 1.0 / 30) - KeyArtPath.ease(12))
        #expect(atTurn < midLeg / 100)
        for c in cases {
            let p = path(c)
            #expect(p.scale(at: 0) == 1 && p.offset(at: 0) == .zero)
            #expect(abs(p.scale(at: 48) - 1) < 1e-9)
        }
    }

    @Test func pushInAndTravelStayInsideTheLimits() {
        for c in cases {
            let p = path(c)
            #expect(p.amplitude <= KeyArtPath.maxScale + 1e-9)
            #expect(hypot(p.drift.dx, p.drift.dy) <= KeyArtPath.maxTravelFraction * c.size.width + 1e-6)
            #expect(p.peakSpeed(in: c.size) <= KeyArtPath.maxSpeed + 1e-6)
        }
    }

    @Test func focalPointStaysInViewAndInTheTopHalfAtAX5() {
        for c in cases {
            let p = path(c)
            for t in times {
                let f = p.apply(p.anchor, at: t)
                #expect(f.x >= 0 && f.x <= c.size.width)
                #expect(f.y >= 0 && f.y <= c.size.height)
                if c.maxY < 1 && c.focal.y <= c.size.height * c.maxY { #expect(f.y <= c.size.height * c.maxY + 1e-6) }
                if c.maxY < 1 && c.focal.y > c.size.height * c.maxY { #expect(f.y <= c.focal.y + 1e-6) }   // never lower than the still
            }
        }
    }

    @Test func artAlwaysCoversTheCover() {
        for c in cases {
            let p = path(c)
            for t in times {
                let topLeft = p.apply(.zero, at: t), bottomRight = p.apply(CGPoint(x: c.size.width, y: c.size.height), at: t)
                #expect(topLeft.x <= 1e-6 && topLeft.y <= 1e-6)
                #expect(bottomRight.x >= c.size.width - 1e-6 && bottomRight.y >= c.size.height - 1e-6)
            }
        }
    }

    /// The murky check: the Wukong key art (a 16 x 16 spread of about 5%) stays still; the other covers move.
    @Test func murkyArtStaysStill() {
        #expect(KeyArtQuality.isMurky(mean: 0.132, spread: 0.053))   // wukong-hero, measured
        #expect(!KeyArtQuality.isMurky(mean: 0.511, spread: 0.197))  // kcd2-hero
        #expect(!KeyArtQuality.isMurky(mean: 0.363, spread: 0.206))  // control-hero
        #expect(KeyArtQuality.isMurky(mean: 0.05, spread: 0.2))      // too dark
        #expect(KeyArtQuality.isMurky(asset: "wukong-hero"))
        #expect(!KeyArtQuality.isMurky(asset: "kcd2-hero"))
    }
}
