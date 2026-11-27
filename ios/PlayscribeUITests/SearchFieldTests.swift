import XCTest

/// bug-search-fields-autocap: the Library, Add and Search tab fields start in lowercase and do not autocorrect.
/// Each test types "c" (Shift would make it "C") and then "wukong" (autocorrect would change it).
@MainActor
final class SearchFieldTests: XCTestCase {
    private func launch(_ route: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", route]
        app.launch()
        return app
    }

    private func check(_ field: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(field.waitForExistence(timeout: 20), "field missing", file: file, line: line)
        field.tap()
        field.typeText("c")
        XCTAssertEqual(field.value as? String, "c", "first letter must be lowercase, no Shift", file: file, line: line)
        field.typeText("lear ")   // finishes a word so autocorrect would act on it
        field.clearText()
        field.typeText("wukong ")
        XCTAssertEqual(field.value as? String, "wukong ", "must not be autocorrected", file: file, line: line)
    }

    func testLibrarySearchStartsLowercase() {
        let app = launch("library/playing")
        check(app.textFields["librarySearchField"])
    }

    func testAddSearchStartsLowercase() {
        let app = launch("add/keyboard")
        check(app.textFields["addSearchField"])
    }

    func testSearchTabStartsLowercase() {
        let app = launch("demo")
        app.tabBars.buttons["Search"].tap()
        check(app.textFields["searchField"])
    }
}

private extension XCUIElement {
    func clearText() {
        guard let text = value as? String, !text.isEmpty else { return }
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count))
    }
}
