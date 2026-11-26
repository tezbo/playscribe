import Testing
@testable import Playscribe

/// Taste pass (Iris): an Open portrait hero card on light art has no veil over the art. heroGround is clear until 55% of the
/// card's height up, eases to 90% by the caption's top edge and holds under the whole caption.
struct HeroGroundRiseTests {
    @Test func clearAboveFiftyFivePercentAndSolidUnderTheCaption() {
        let b = HeroGroundRise.bands(cardHeight: 300, captionHeight: 120, reach: 0.55, minRamp: 40)
        #expect(b.solid == 120, "the whole caption sits on the solid part")
        #expect(b.ramp + b.solid == 165, "nothing is drawn above 55% of the card's height")
    }

    @Test func aTallCaptionStillEasesIn() {
        let b = HeroGroundRise.bands(cardHeight: 300, captionHeight: 250, reach: 0.55, minRamp: 40)
        #expect(b.solid == 250)
        #expect(b.ramp == 40, "at least 40 pt of ease above a caption taller than 55%, so there is no hard edge")
    }

    @Test func neverTallerThanTheCard() {
        let b = HeroGroundRise.bands(cardHeight: 200, captionHeight: 190, reach: 0.55, minRamp: 40)
        #expect(b.ramp + b.solid <= 200)
        #expect(b.solid == 190)
    }
}
