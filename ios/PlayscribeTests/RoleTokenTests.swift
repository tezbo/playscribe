import Testing
import UIKit
@testable import Playscribe

/// s-06-01-tokens: Iris's 0.6 light values (design/tokens-0.6-light-values.md). Ratios are the ones in her table.
struct RoleTokenTests {
    private func light(_ s: PlayscribeRole.Spec) -> UIColor { PlayscribeRole.resolved(s, light: true) }
    private func dark(_ s: PlayscribeRole.Spec) -> UIColor { PlayscribeRole.resolved(s, light: false) }
    private func ratio(_ a: PlayscribeRole.Spec, _ b: PlayscribeRole.Spec) -> Double { Contrast.ratio(light(a), light(b)) }

    @Test func lightHexValuesAreIrissTable() {
        let expected: [String: UInt32] = [
            "bg": 0xFBF4E6, "card": 0xF4EEE3, "chipFill": 0xEAE1D0, "textPrimary": 0x1B1822, "textSecondary": 0x5A5260,
            "textTertiary": 0x6B6370, "newText": 0xA04E0D, "newGraphic": 0xB45A12, "action": 0xA04E0D, "onAction": 0xFBF4E6,
            "link": 0xA04E0D, "selectedChipFill": 0xE3D2B3, "selectedChipText": 0x1B1822, "controlBorder": 0x857A68, "hairline": 0xCFC4B0,
        ]
        for (name, hex) in expected {
            let spec = PlayscribeRole.all.first { $0.name == name }
            #expect(spec?.light == hex, "\(name)")
        }
    }

    @Test func textMeetsFourPointFiveOnItsSurfaces() {
        let bg = PlayscribeRole.bgSpec, card = PlayscribeRole.cardSpec, chip = PlayscribeRole.chipFillSpec
        #expect(ratio(PlayscribeRole.textPrimarySpec, bg) >= 15.9)
        #expect(ratio(PlayscribeRole.textPrimarySpec, card) >= 15.1)
        for surface in [bg, card, chip] { #expect(ratio(PlayscribeRole.textSecondarySpec, surface) >= 5.7) }
        for surface in [bg, card] { #expect(ratio(PlayscribeRole.textTertiarySpec, surface) >= 4.9) }
        for surface in [bg, card, chip] { #expect(ratio(PlayscribeRole.newTextSpec, surface) >= 4.5) }
        #expect(ratio(PlayscribeRole.linkSpec, bg) >= 5.3)
        #expect(ratio(PlayscribeRole.selectedChipTextSpec, PlayscribeRole.selectedChipFillSpec) >= 11.7)
    }

    @Test func actionLabelAndGraphicsMeetTheirFloors() {
        #expect(ratio(PlayscribeRole.onActionSpec, PlayscribeRole.actionSpec) >= 5.3)
        // The unread star and dot are graphics: 3:1 is the floor, not 4.5:1.
        #expect(ratio(PlayscribeRole.newGraphicSpec, PlayscribeRole.bgSpec) >= 3)
        // Control boundaries need 3:1 against the surfaces they sit on.
        #expect(ratio(PlayscribeRole.controlBorderSpec, PlayscribeRole.bgSpec) >= 3.8)
        #expect(ratio(PlayscribeRole.controlBorderSpec, PlayscribeRole.cardSpec) >= 3.6)
    }

    @Test func emberIsNeverTextOnLight() {
        // #FFB04F on the light ground is about 1.7:1; no light role may be it.
        let ember = UIColor(hex: 0xFFB04F)
        #expect(Contrast.ratio(ember, light(PlayscribeRole.bgSpec)) < 2)
        for spec in PlayscribeRole.all { #expect(spec.light != 0xFFB04F, "\(spec.name)") }
    }

    @Test func newAndActionAreSeparateRolesThatShareDark() {
        #expect(PlayscribeRole.newTextSpec.name != PlayscribeRole.actionSpec.name)
        let a = dark(PlayscribeRole.newTextSpec), b = dark(PlayscribeRole.actionSpec), g = dark(PlayscribeRole.newGraphicSpec)
        #expect(Contrast.ratio(a, b) == 1 && Contrast.ratio(a, g) == 1)
    }

    @Test func darkValuesAreTheOldColours() {
        func rgb(_ c: UIColor) -> [Int] {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            return [r, g, b, a].map { Int(($0 * 1000).rounded()) }
        }
        #expect(rgb(dark(PlayscribeRole.bgSpec)) == rgb(UIColor(PlayscribeColor.ink950)))
        #expect(rgb(dark(PlayscribeRole.surfaceSpec)) == rgb(UIColor(PlayscribeColor.ink900)))
        #expect(rgb(dark(PlayscribeRole.cardSpec)) == rgb(UIColor(PlayscribeColor.ink800)))
        #expect(rgb(dark(PlayscribeRole.chipFillSpec)) == rgb(UIColor(PlayscribeColor.ink700)))
        #expect(rgb(dark(PlayscribeRole.textPrimarySpec)) == rgb(UIColor(PlayscribeColor.textPrimary)))
        #expect(rgb(dark(PlayscribeRole.actionSpec)) == rgb(UIColor(PlayscribeColor.accent)))
        #expect(rgb(dark(PlayscribeRole.onActionSpec)) == rgb(UIColor(PlayscribeColor.onAccent)))
        // The 0.5 dark checks: secondary on ink 7.91, ember on ink 10.59, button label on ember 9.45.
        let ink = dark(PlayscribeRole.bgSpec)
        #expect(Contrast.ratio(dark(PlayscribeRole.textSecondarySpec), ink) > 7)
        #expect(Contrast.ratio(dark(PlayscribeRole.actionSpec), ink) > 10)
        #expect(Contrast.ratio(dark(PlayscribeRole.onActionSpec), dark(PlayscribeRole.actionSpec)) > 9)
    }

    @Test func rolesFollowTheColourScheme() {
        let c = PlayscribeRole.uiColor(PlayscribeRole.bgSpec)
        let l = c.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let d = c.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        #expect(Contrast.ratio(l, d) > 10)
    }
}
