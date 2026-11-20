import XCTest

final class ReaderUITests: XCTestCase {
    @MainActor
    func testEmptyLibraryShowsImportControlsAndPickerCanCancel() {
        let app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        app.launch()
        XCTAssertTrue(app.staticTexts["Chưa có sách"].waitForExistence(timeout: 10))
        let importButton = app.buttons["empty-import-book"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["import-book"].exists)
        importButton.tap()
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 30))
        cancel.tap()
        XCTAssertTrue(app.staticTexts["Chưa có sách"].waitForExistence(timeout: 5))
    }
}
