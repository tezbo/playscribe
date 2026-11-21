import Foundation

/// R-7 (0.5.6 redesign, Card C, /mnt/project-files/design/redesign-0.6/spec.md): the game page's sections.
/// Five, in a fixed order: What's new, News, Companion, Gallery, My book. World and Companion are one section,
/// Companion, with a World / Tips filter inside only when the game has both kinds. Empty sections hide.
/// Pure, so the rules are unit tested apart from the views (GameSectionsTests).
enum GameSections {
    /// The fixed order. `Chapter.world` is not a section any more: it stays in the enum only so saved state from
    /// 0.5.5 and earlier (D-13 per-game chapter, `chapter/<game>/world` routes) still decodes, and reads as Companion.
    static let order: [Chapter] = [.updates, .news, .companion, .gallery, .mybook]

    /// What the game has, for deciding which sections show.
    struct Content: Equatable {
        /// Companion entries of each kind (BookEntry.Chapter: world, companion).
        var worldEntries = 0
        var tipEntries = 0
        /// News: nil while it has not loaded (or failed), else the number of headlines.
        var newsCount: Int?
        var galleryItems = 0
    }

    /// The sections to show, in order.
    /// - What's new always shows: it carries the no-release hero and the basics, so no game opens blank.
    /// - My book always shows: it is where a note is written, so it is never empty as a place.
    /// - News hides only once it has loaded with nothing. While it loads, or after a failure (which offers Retry), it shows.
    /// - Companion hides with no entries of either kind; Gallery with no items.
    /// - News stays while it is `current` (on screen), so it never disappears under the reader when its headlines arrive
    ///   empty; it hides the next time the game opens. (News is the only section whose content arrives after the page.)
    static func visible(_ c: Content, current: Chapter? = nil) -> [Chapter] {
        order.filter { s in
            switch s {
            case .updates, .mybook: return true
            case .news: return current == .news || (c.newsCount.map { $0 > 0 } ?? true)
            case .companion, .world: return c.worldEntries + c.tipEntries > 0
            case .gallery: return c.galleryItems > 0
            }
        }
    }

    /// World reads as Companion; every other section is itself.
    static func canonical(_ s: Chapter) -> Chapter { s == .world ? .companion : s }

    /// The section to show for a stored one: itself (World as Companion) when visible, else What's new.
    static func resolve(_ stored: Chapter, in visible: [Chapter]) -> Chapter {
        let s = canonical(stored)
        return visible.contains(s) ? s : .updates
    }

    /// The Companion filter's choices: World and Tips, only when the game has both; otherwise none (no filter shown).
    static func companionFilters(_ c: Content) -> [BookEntry.Chapter] {
        c.worldEntries > 0 && c.tipEntries > 0 ? [.world, .companion] : []
    }

    /// The kind the Companion section lists: the stored filter when the filter shows, else nil (every entry).
    static func companionKind(_ stored: BookEntry.Chapter?, _ c: Content) -> BookEntry.Chapter? {
        let filters = companionFilters(c)
        guard !filters.isEmpty else { return nil }
        return stored.flatMap { filters.contains($0) ? $0 : nil } ?? filters[0]
    }

    /// The filter's label for a kind.
    static func filterTitle(_ k: BookEntry.Chapter) -> String { k == .world ? "World" : "Tips" }
}
