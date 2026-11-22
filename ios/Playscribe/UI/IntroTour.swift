import SwiftUI

/// 6b, r060-intro-tour (handoff/0.6.0-intro-tour.md, copy in handoff/0.6.0/intro-tour-copy.md): a welcome, then three short
/// steps, skippable at every point. It never replays by itself; Settings has "Replay tour".
enum TourStep: Int, CaseIterable, Codable {
    case openGame, updates, spoiler

    var number: Int { rawValue + 1 }
    var counter: String { "\(number) of \(Self.allCases.count)" }
    var isLast: Bool { self == Self.allCases.last }
    var next: TourStep? { TourStep(rawValue: rawValue + 1) }
    var primary: String { isLast ? "Done" : "Next" }

    var title: String {
        switch self {
        case .openGame: "Open a game"
        case .updates: "Everything new"
        case .spoiler: "Spoiler-safe"
        }
    }

    /// The spec's copy; an empty Library gets the longer step 1 and 2 bodies.
    func body(emptyLibrary: Bool) -> String {
        switch self {
        case .openGame:
            emptyLibrary ? "Tap any game to read its latest update. Opening one does not add it to your Library."
                : "Tap any game to read its latest update."
        case .updates:
            emptyLibrary ? "Updates gathers every patch for your games, newest first. Add games and they appear here."
                : "Updates gathers every patch for your games, newest first."
        case .spoiler: "Story details stay hidden until you choose to show them."
        }
    }

    /// VoiceOver on each new step: "Tour, step 1 of 3. Open a game. Tap any game to read its latest update."
    func announcement(emptyLibrary: Bool) -> String {
        "Tour, step \(number) of \(Self.allCases.count). \(title). \(body(emptyLibrary: emptyLibrary))"
    }
}

enum TourCopy {
    static let welcomeTitle = "Welcome to Playscribe"
    static let welcomeLine = "Every PS5 patch for the games you play, in one place."
    static let take = "Take a 30-second tour"
    static let skip = "Skip"
    static let skipTour = "Skip tour"
    static let replay = "Replay tour"
    static let replayFooter = "Walk through the main screens again."
}

// MARK: - Anchors

/// Frames of the views a step points at, in the Duo container's space. Several views may offer the same step (every Library
/// tile offers step 1); the overlay picks the first one on screen.
struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [TourStep: [CGRect]] = [:]
    static func reduce(value: inout [TourStep: [CGRect]], nextValue: () -> [TourStep: [CGRect]]) {
        value.merge(nextValue()) { $0 + $1 }
    }
}

private struct TourAnchorReporter: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.auditActive) private var active
    var step: TourStep?

    func body(content: Content) -> some View {
        // Only while that step shows: a reader on every tile on each scroll frame made long pages lag (0.2.0).
        if let step, model.tourStep == step, active {
            content.background {
                GeometryReader { g in
                    Color.clear.preference(key: TourAnchorKey.self, value: [step: [g.frame(in: .named(DuoContext.space))]])
                }
            }
        } else {
            content
        }
    }
}

extension View {
    /// Offers this view as the target of a tour step (nil: none).
    func tourAnchor(_ step: TourStep?) -> some View { modifier(TourAnchorReporter(step: step)) }
}

// MARK: - Placement (pure, unit tested)

enum TourLayout {
    static let maxWidth: CGFloat = 320
    static let margin: CGFloat = 16
    static let gap: CGFloat = 12
    /// Room kept for the bottom tab bar in the portrait poses.
    static let tabBarReserve: CGFloat = 96

    /// The first candidate on screen: inside the container, the top-most, then the leading-most. In Tabletop only the lower half
    /// counts, since nothing above the fold is tappable or pointed at (G-4).
    static func target(_ rects: [CGRect], container: CGSize, pose: Pose, division: CGRect?) -> CGRect? {
        let bounds = CGRect(origin: .zero, size: container)
        let floor = pose == .tabletop ? (division?.maxY ?? 0) : 0
        return rects
            .filter { !$0.isEmpty && bounds.insetBy(dx: -1, dy: -1).contains($0) && $0.minY >= floor - 1 }
            .min { ($0.minY, $0.minX) < ($1.minY, $1.minX) }
    }

    /// The card's frame. Tabletop: a bottom card in the lower half, clear of the rail. Book: on the page that holds the target
    /// (the left page when there is none), 25 pt clear of the hinge. Elsewhere: below the target when it fits, else above it,
    /// else at the top; with no target (the text-only card), above the tab bar.
    static func card(size: CGSize, target: CGRect?, container: CGSize, pose: Pose, division: CGRect?, safeArea: EdgeInsets,
                     landscape: Bool, railWidth: CGFloat) -> CGRect {
        var minX = margin, maxX = container.width - margin
        if pose == .tabletop {
            maxX = container.width - railWidth - gap
        } else if pose == .book, let d = division {
            let right = (target?.midX ?? 0) > d.midX
            if right { minX = d.maxX + DuoContext.hingeGap } else { maxX = d.minX - DuoContext.hingeGap }
        }
        let width = min(maxWidth, max(0, maxX - minX))
        let height = size.height
        if pose == .tabletop {
            let top = (division?.maxY ?? 0) + gap
            let y = max(top, container.height - safeArea.bottom - gap - height)
            return CGRect(x: minX, y: y, width: max(0, maxX - minX), height: height)
        }
        let x = min(max(minX, (target?.midX ?? (minX + maxX) / 2) - width / 2), maxX - width)
        let top = safeArea.top + 8
        let bottom = container.height - (landscape ? safeArea.bottom + margin : max(safeArea.bottom, 0) + tabBarReserve)
        guard let t = target else { return CGRect(x: x, y: max(top, bottom - height), width: width, height: height) }
        if t.maxY + gap + height <= bottom { return CGRect(x: x, y: t.maxY + gap, width: width, height: height) }
        if t.minY - gap - height >= top { return CGRect(x: x, y: t.minY - gap - height, width: width, height: height) }
        return CGRect(x: x, y: top, width: width, height: height)
    }
}

// MARK: - Overlay

/// The ring on the target and the step card (or the welcome). Lives over the whole app in RootView; hidden while any sheet or
/// panel is open, and back on the same step when it closes.
struct TourOverlay: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    var duo: DuoContext
    var anchors: [TourStep: [CGRect]]
    @State private var cardSize: CGSize = .zero
    @AccessibilityFocusState private var focused: Bool

    private var covered: Bool {
        model.addSheetOpen || model.settingsOpen || model.linksSheetOpen || model.tagExplainer != nil
            || model.keepCurrentDetailsOpen || model.player != nil || model.trailer != nil || model.shareReleaseID != nil
    }
    private var empty: Bool { model.data.collection.isEmpty }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !covered, model.tourWelcome || model.tourStep != nil {
                let step = model.tourStep
                let target = step.flatMap { anchors[$0] }.flatMap {
                    TourLayout.target($0, container: duo.size, pose: duo.pose, division: duo.division)
                }
                if let target {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(PlayscribeColor.vellum500, lineWidth: 2)
                        .frame(width: target.width + 8, height: target.height + 8)
                        .offset(x: target.minX - 4, y: target.minY - 4)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
                let frame = TourLayout.card(size: cardSize, target: target, container: duo.size, pose: duo.pose,
                                            division: duo.division, safeArea: duo.safeArea, landscape: duo.isLandscape,
                                            railWidth: TabletopRail.width)
                card(step: step)
                    .frame(width: frame.width)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { cardSize = $0 }
                    .offset(x: frame.minX, y: frame.minY)
                    .opacity(cardSize == .zero ? 0 : 1)
                    .transition(.opacity)
            }
        }
        .frame(width: duo.size.width, height: duo.size.height, alignment: .topLeading)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.25), value: model.tourStep)
        .animation(.easeInOut(duration: 0.2), value: covered)
        .onChange(of: model.tourStep, initial: true) { _, step in
            guard let step else { return }
            AccessibilityNotification.Announcement(step.announcement(emptyLibrary: empty)).post()
            focused = true
        }
    }

    @ViewBuilder private func card(step: TourStep?) -> some View {
        let maxHeight = duo.pose == .tabletop
            ? max(120, duo.size.height - (duo.division?.maxY ?? 0) - duo.safeArea.bottom - 2 * TourLayout.gap)
            : duo.size.height * 0.5
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if let step {
                        Text(step.counter).font(PlayscribeFont.footnote).foregroundStyle(PlayscribeRole.textSecondary)
                            .accessibilityHidden(true)
                        Text(step.title).font(PlayscribeFont.headline).foregroundStyle(PlayscribeRole.textPrimary)
                            .accessibilityLabel("Tour, step \(step.number) of \(TourStep.allCases.count). \(step.title)")
                            .accessibilityFocused($focused)
                        Text(step.body(emptyLibrary: empty)).font(PlayscribeFont.body).foregroundStyle(PlayscribeRole.textPrimary)
                    } else {
                        Text(TourCopy.welcomeTitle).font(PlayscribeFont.title3).foregroundStyle(PlayscribeRole.textPrimary)
                            .accessibilityFocused($focused)
                        Text(TourCopy.welcomeLine).font(PlayscribeFont.body).foregroundStyle(PlayscribeRole.textPrimary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: max(60, maxHeight - (typeSize.isAccessibilitySize ? 140 : 76)))
            .fixedSize(horizontal: false, vertical: !typeSize.isAccessibilitySize)
            buttons(step: step)
        }
        .padding(16)
        .background(PlayscribeRole.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(PlayscribeColor.vellum300.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(step == nil ? "tourWelcome" : "tourCard")
        .onAppear { if model.tourWelcome { focused = true } }
    }

    @ViewBuilder private func buttons(step: TourStep?) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            if let step {
                secondary(TourCopy.skipTour) { model.endTour() }
                    .accessibilityHint("Ends the tour. You can replay it in Settings")
                primary(step.primary) { model.advanceTour() }
                    .accessibilityHint(step.isLast ? "Finishes the tour" : "Shows the next tip")
            } else {
                secondary(TourCopy.skip) { model.endTour() }
                    .accessibilityHint("Goes to your Library. You can replay the tour in Settings")
                primary(TourCopy.take) { model.startTour() }
                    .accessibilityHint("Shows three short tips")
            }
        }
    }

    private func primary(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(PlayscribeFont.headline).foregroundStyle(PlayscribeRole.onAction)
                .padding(.horizontal, 14)
                .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, minHeight: 44)
                .background(PlayscribeRole.action, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .tappableFrame()
    }

    private func secondary(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(PlayscribeFont.headline).foregroundStyle(PlayscribeRole.action)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: typeSize.isAccessibilitySize ? .center : .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tappableFrame()
    }
}
