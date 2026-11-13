import SwiftUI
import UIKit

/// 0.6 semantic colour roles (s-06-01-tokens; values and rules in design/tokens-0.6-light-values.md, Iris).
/// Views read a role, never a hex. Every role has a light and a dark value; the dark values are the 0.5 colours, unchanged.
/// `new` and `action` are two roles that share one dark value (#FFB04F) so they can diverge later; `new` is for unread items only.
/// Scrims and covers are not roles: they keep `PlayscribeColor.ink950` and stay dark in both modes.
enum PlayscribeRole {
    /// One row of the role table: the light hex, and the dark colour it replaces.
    struct Spec {
        var name: String
        var light: UInt32
        var dark: Color
        var darkAlpha: Double = 1
    }

    // Surfaces.
    static let bgSpec = Spec(name: "bg", light: 0xFBF4E6, dark: PlayscribeColor.ink950)
    /// The raised panel one step above `bg` in dark (ink900); the same card cream in light.
    static let surfaceSpec = Spec(name: "surface", light: 0xF4EEE3, dark: PlayscribeColor.ink900)
    static let cardSpec = Spec(name: "card", light: 0xF4EEE3, dark: PlayscribeColor.ink800)
    static let chipFillSpec = Spec(name: "chipFill", light: 0xEAE1D0, dark: PlayscribeColor.ink700)
    // Text.
    static let textPrimarySpec = Spec(name: "textPrimary", light: 0x1B1822, dark: PlayscribeColor.textPrimary)
    static let textSecondarySpec = Spec(name: "textSecondary", light: 0x5A5260, dark: PlayscribeColor.textSecondary)
    static let textTertiarySpec = Spec(name: "textTertiary", light: 0x6B6370, dark: PlayscribeColor.textTertiary)
    // Unread (`new`) and interactive (`action`) share a hue and nothing else.
    static let newTextSpec = Spec(name: "newText", light: 0xA04E0D, dark: PlayscribeColor.accent)
    static let newGraphicSpec = Spec(name: "newGraphic", light: 0xB45A12, dark: PlayscribeColor.accent)
    static let actionSpec = Spec(name: "action", light: 0xA04E0D, dark: PlayscribeColor.accent)
    static let onActionSpec = Spec(name: "onAction", light: 0xFBF4E6, dark: PlayscribeColor.onAccent)
    static let linkSpec = Spec(name: "link", light: 0xA04E0D, dark: PlayscribeColor.accent)
    static let selectedChipFillSpec = Spec(name: "selectedChipFill", light: 0xE3D2B3, dark: PlayscribeColor.accent, darkAlpha: 0.22)
    static let selectedChipTextSpec = Spec(name: "selectedChipText", light: 0x1B1822, dark: PlayscribeColor.textPrimary)
    // Lines.
    static let controlBorderSpec = Spec(name: "controlBorder", light: 0x857A68, dark: PlayscribeColor.ink600)
    static let hairlineSpec = Spec(name: "hairline", light: 0xCFC4B0, dark: PlayscribeColor.ink700)

    static let all: [Spec] = [bgSpec, surfaceSpec, cardSpec, chipFillSpec, textPrimarySpec, textSecondarySpec, textTertiarySpec,
                              newTextSpec, newGraphicSpec, actionSpec, onActionSpec, linkSpec, selectedChipFillSpec,
                              selectedChipTextSpec, controlBorderSpec, hairlineSpec]

    static let bg = color(bgSpec)
    static let surface = color(surfaceSpec)
    static let card = color(cardSpec)
    static let chipFill = color(chipFillSpec)
    static let textPrimary = color(textPrimarySpec)
    static let textSecondary = color(textSecondarySpec)
    static let textTertiary = color(textTertiarySpec)
    static let newText = color(newTextSpec)
    static let newGraphic = color(newGraphicSpec)
    static let action = color(actionSpec)
    static let onAction = color(onActionSpec)
    static let link = color(linkSpec)
    static let selectedChipFill = color(selectedChipFillSpec)
    static let selectedChipText = color(selectedChipTextSpec)
    static let controlBorder = color(controlBorderSpec)
    static let hairline = color(hairlineSpec)

    /// The role as a colour that follows the environment's colour scheme (a view forced dark, such as a cover, gets the dark value).
    static func color(_ spec: Spec) -> Color { Color(uiColor(spec)) }

    static func uiColor(_ spec: Spec) -> UIColor {
        UIColor { traits in resolved(spec, light: traits.userInterfaceStyle == .light) }
    }

    /// The colour of a role in one scheme, for the contrast tests.
    static func resolved(_ spec: Spec, light: Bool) -> UIColor {
        if light { return UIColor(hex: spec.light) }
        return UIColor(spec.dark).withAlphaComponent(spec.darkAlpha)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// WCAG 2.x relative luminance and contrast, for the role tests.
enum Contrast {
    static func luminance(_ c: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ v: CGFloat) -> Double { let x = Double(v); return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    static func ratio(_ a: UIColor, _ b: UIColor) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}
