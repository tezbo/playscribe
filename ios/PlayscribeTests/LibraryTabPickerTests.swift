import SwiftUI
import Testing
@testable import Playscribe

/// J-11: the Playing / Upcoming switch is two chips at every accessibility size, the segmented control below them
/// (bug-playing-upcoming-switch-ax5-small).
struct LibraryTabPickerTests {
    @Test(arguments: DynamicTypeSize.allCases)
    func chipsExactlyAtAccessibilitySizes(_ size: DynamicTypeSize) {
        #expect(LibraryTabPicker.usesChips(size) == (size >= .accessibility1))
    }
}
