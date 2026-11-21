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
    /// Fields, search fields and outlined buttons (s-06-control-border). Dark is clear: in 0.5 these controls had no border, and
    /// dark is unchanged. A control that already had a dark border keeps it with `controlBorder(keepingDark:)`.
    static let controlBorderSpec = Spec(name: "controlBorder", light: 0x857A68, dark: .clear, darkAlpha: 0)
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

    /// The control border in light, and the colour this control already drew in dark (dark is unchanged by 0.6).
    /// The dark colour's own alpha carries through: `.withAlphaComponent(1)` would turn `.clear` into opaque black (screen diffs
    /// on 1c086d4 showed a dark outline on every field).
    static func controlBorder(keepingDark dark: Color) -> Color {
        var alpha: CGFloat = 0
        UIColor(dark).getRed(nil, green: nil, blue: nil, alpha: &alpha)
        return color(Spec(name: controlBorderSpec.name, light: controlBorderSpec.light, dark: dark, darkAlpha: Double(alpha)))
    }

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

/// The controls that draw the control border (s-06-control-border; Iris: "fields, outlined buttons and any control boundary use
/// the control border value, not the hairline"). Each call site names its kind, so the test can list them.
enum ControlKind: String, CaseIterable {
    /// A search field drawn by us: magnifier, field, chip fill.
    case searchField
    /// A free-text field (notes, a custom game's name).
    case textField
    /// Tabletop's read-only search button, which stands in for a field.
    case tabletopSearch
    /// A secondary button in the bordered style ("Not now", Bookmark, Mark as read).
    case outlinedButton
    /// The solid ink panel that replaces glass under Reduce Transparency or Increase Contrast.
    case solidGlass
}

private struct ControlBorder<S: InsettableShape>: ViewModifier {
    var shape: S
    var dark: Color
    var horizontalOutset: CGFloat
    func body(content: Content) -> some View {
        content.overlay {
            shape.strokeBorder(PlayscribeRole.controlBorder(keepingDark: dark), lineWidth: 1)
                .padding(.horizontal, -horizontalOutset)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    /// A 1 pt control border in `shape`: #857A68 in light (3:1 or better on bg and card); in dark, `keepingDark`, which is clear
    /// unless the control already had a border there.
    /// `horizontalOutset` draws the border that far outside the frame on each side, for a field whose text must not move.
    func controlBorder<S: InsettableShape>(_ kind: ControlKind, in shape: S, keepingDark dark: Color = .clear,
                                           horizontalOutset: CGFloat = 0) -> some View {
        modifier(ControlBorder(shape: shape, dark: dark, horizontalOutset: horizontalOutset))
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
