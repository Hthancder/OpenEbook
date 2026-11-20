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

    @MainActor
    func testTXTSearchAndBookmarkRestoreAfterRelaunch() {
        let (app, fixtureID) = launchReaderFixtures()
        let title = "Reader TXT \(fixtureID)"
        let searchTitle = "Tìm trong văn bản"
        let menuTitle = "Công cụ đọc"
        let bookmarkTitle = "Dòng 21"
        let scrollView = app.scrollViews.firstMatch
        let start = scrollView.staticTexts["StartMarker"]
        let target = scrollView.staticTexts["TargetMarker"]
        let result = app.buttons["Dòng 21: TargetMarker"]

        openFixture(titled: title, in: app)
        XCTAssertTrue(waitForVisible(start), "The TXT reader should start at StartMarker.")
        attachReaderScreenshot("TXT opened at StartMarker", in: app)
        tapVisible(app.buttons["text-search-button"])
        let field = app.textFields["text-search-field"]
        tapVisible(field)
        field.typeText("TargetMarker")
        XCTAssertTrue(waitForVisible(result), "The search sheet should show the matching TXT line.")

        // Typing can jump to the first hit. Move away so only selecting the row can pass.
        closeSheet(searchTitle, in: app)
        scrollAwayFromTXTTarget(scrollView, target: target)
        tapVisible(app.buttons["text-search-button"])
        tapVisible(result)
        waitForSheetToClose(searchTitle, in: app)
        XCTAssertTrue(waitForVisible(target), "Selecting the TXT result should bring TargetMarker into view.")
        attachReaderScreenshot("TXT after selecting TargetMarker", in: app)

        addBookmark("Đánh dấu dòng 21", menuTitle: menuTitle, in: app)
        scrollAwayFromTXTTarget(scrollView, target: target)
        let bookmark = openBookmarks(titled: bookmarkTitle, menuTitle: menuTitle, in: app)
        tapVisible(bookmark)
        waitForSheetToClose("Dấu trang", in: app)
        XCTAssertTrue(waitForVisible(target), "Selecting the TXT bookmark should return to TargetMarker.")

        app.terminate()
        app.launch()
        openFixture(titled: title, in: app)
        XCTAssertTrue(waitForVisible(target), "The TXT reader should reopen at TargetMarker.")
        XCTAssertFalse(start.exists && start.isHittable, "The TXT reader should not reopen at the start.")
        attachReaderScreenshot("TXT restored at TargetMarker", in: app)
        _ = openBookmarks(titled: bookmarkTitle, menuTitle: menuTitle, in: app, currentAction: "Đánh dấu dòng 21")
        attachReaderScreenshot("TXT saved bookmark for line 21", in: app)
        closeSheet("Dấu trang", in: app)
    }

    @MainActor
    func testPDFSearchAndBookmarkRestoreAfterRelaunch() {
        let (app, fixtureID) = launchReaderFixtures()
        let title = "Reader PDF \(fixtureID)"
        let searchTitle = "Tìm trong PDF"
        let menuTitle = "Dấu trang và nội dung PDF"
        let bookmarkTitle = "Trang 3"
        // The visual counter is “Trang N / 3”; VoiceOver exposes “Trang N trên 3”.
        let firstPage = app.staticTexts["Trang 1 trên 3"]
        let thirdPage = app.staticTexts["Trang 3 trên 3"]
        let result = app.buttons["pdf-search-result-0"]

        openFixture(titled: title, in: app)
        XCTAssertTrue(waitForVisible(firstPage), "The imported three-page PDF should open on page 1.")
        attachReaderScreenshot("PDF opened on page 1 of 3", in: app)
        tapVisible(app.buttons["pdf-search-button"])
        let field = app.textFields["pdf-search-field"]
        tapVisible(field)
        field.typeText("PDFMarker3")
        XCTAssertTrue(waitForVisible(result), "The search sheet should show the PDFMarker3 result.")
        XCTAssertTrue(result.label.contains("PDFMarker3"), "The selected PDF result must contain the queried text.")

        closeSheet(searchTitle, in: app)
        scrollBackToFirstPDFPage(in: app, firstPage: firstPage)
        tapVisible(app.buttons["pdf-search-button"])
        tapVisible(result)
        waitForSheetToClose(searchTitle, in: app)
        XCTAssertTrue(waitForVisible(thirdPage), "Selecting the PDF result should jump to page 3.")
        attachReaderScreenshot("PDF after selecting PDFMarker3 on page 3 of 3", in: app)

        addBookmark("Đánh dấu trang 3", menuTitle: menuTitle, in: app)
        scrollBackToFirstPDFPage(in: app, firstPage: firstPage)
        let bookmark = openBookmarks(titled: bookmarkTitle, menuTitle: menuTitle, in: app)
        tapVisible(bookmark)
        waitForSheetToClose("Dấu trang", in: app)
        XCTAssertTrue(waitForVisible(thirdPage), "Selecting the PDF bookmark should return to page 3.")

        app.terminate()
        app.launch()
        openFixture(titled: title, in: app)
        XCTAssertTrue(waitForVisible(thirdPage), "The PDF should reopen on page 3 of 3.")
        attachReaderScreenshot("PDF restored on page 3 of 3", in: app)
        _ = openBookmarks(titled: bookmarkTitle, menuTitle: menuTitle, in: app)
        attachReaderScreenshot("PDF saved bookmark for page 3", in: app)
        closeSheet("Dấu trang", in: app)
    }

    @MainActor
    private func launchReaderFixtures() -> (XCUIApplication, String) {
        continueAfterFailure = false
        let fixtureID = UUID().uuidString
        let app = XCUIApplication()
        app.launchArguments.append("--uitesting-readers")
        app.launchEnvironment["BOOKREADER_TEST_FIXTURE_ID"] = fixtureID
        app.launch()
        return (app, fixtureID)
    }

    @MainActor
    private func openFixture(titled title: String, in app: XCUIApplication) {
        // The same book may also appear under “Đọc tiếp” after it has been read.
        let card = app.buttons.matching(NSPredicate(format: "label == %@", "Mở \(title)")).firstMatch
        tapVisible(card, timeout: 30)
    }

    @MainActor
    private func addBookmark(_ actionTitle: String, menuTitle: String, in app: XCUIApplication) {
        tapVisible(app.buttons[menuTitle])
        tapVisible(app.buttons[actionTitle])
        let confirmation = app.alerts["Thông báo"]
        XCTAssertTrue(waitForVisible(confirmation.staticTexts["Đã thêm dấu trang."]))
        tapVisible(confirmation.buttons["Đóng"])
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: confirmation)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed, "Expected bookmark confirmation to close.")
    }

    @MainActor
    private func openBookmarks(
        titled title: String, menuTitle: String, in app: XCUIApplication, currentAction: String? = nil
    ) -> XCUIElement {
        tapVisible(app.buttons[menuTitle])
        if let currentAction {
            XCTAssertTrue(waitForVisible(app.buttons[currentAction]), "Expected reader location: \(currentAction).")
        }
        tapVisible(app.buttons["Dấu trang"])
        XCTAssertTrue(app.navigationBars["Dấu trang"].waitForExistence(timeout: 5))
        let bookmark = app.buttons[title]
        XCTAssertTrue(waitForVisible(bookmark), "Dấu trang should contain \(title).")
        return bookmark
    }

    @MainActor
    private func closeSheet(_ title: String, in app: XCUIApplication) {
        tapVisible(app.navigationBars[title].buttons["Đóng"])
        waitForSheetToClose(title, in: app)
    }

    @MainActor
    private func waitForSheetToClose(_ title: String, in app: XCUIApplication) {
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.navigationBars[title]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed, "Expected \(title) to close.")
    }

    @MainActor
    private func scrollAwayFromTXTTarget(_ scrollView: XCUIElement, target: XCUIElement) {
        scrollView.swipeUp()
        scrollView.swipeUp()
        XCTAssertFalse(target.exists && target.isHittable, "Move past TargetMarker before testing the jump back.")
    }

    @MainActor
    private func scrollBackToFirstPDFPage(in app: XCUIApplication, firstPage: XCUIElement) {
        let document = app.descendants(matching: .any).matching(identifier: "pdf-document-view").firstMatch
        XCTAssertTrue(document.waitForExistence(timeout: 5))
        document.swipeDown()
        document.swipeDown()
        XCTAssertTrue(waitForVisible(firstPage), "Return to page 1 before testing the jump to page 3.")
    }

    @MainActor
    private func tapVisible(_ element: XCUIElement, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitForVisible(element, timeout: timeout), "Expected a visible control: \(element)", file: file, line: line)
        element.tap()
    }

    @MainActor
    private func waitForVisible(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.exists && element.isHittable
        }, object: nil)
        return XCTWaiter.wait(for: [visible], timeout: timeout) == .completed
    }

    @MainActor
    private func attachReaderScreenshot(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
