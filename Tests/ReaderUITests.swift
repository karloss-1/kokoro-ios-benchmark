import XCTest

@MainActor final class ReaderUITests: XCTestCase {
    func snapshot(_ name: String) {
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        item.name = name; item.lifetime = .keepAlways; add(item)
    }
    func chooseFixture(_ app: XCUIApplication, kind: String, stem: String) {
        app.buttons["addToLibrary"].tap()
        app.buttons.containing(.staticText, identifier: "Import " + kind).firstMatch.tap()
        let localFiles = app.staticTexts.matching(NSPredicate(format: "label IN %@", ["On My iPhone", "On My iPad"])).firstMatch
        let browserReady = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["On My iPhone", "On My iPad", "Browse"])).firstMatch
        XCTAssertTrue(browserReady.waitForExistence(timeout: 15))
        if !localFiles.exists {
            XCTAssertTrue(app.buttons["Browse"].waitForExistence(timeout: 10))
            app.buttons["Browse"].tap()
        }
        if localFiles.waitForExistence(timeout: 2) { localFiles.tap() }
        if app.staticTexts["Document Reader"].waitForExistence(timeout: 2) { app.staticTexts["Document Reader"].firstMatch.tap() }
        let folder = app.cells["Validation fixtures, Folder"]
        if folder.waitForExistence(timeout: 3) { folder.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap() }
        let file = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", stem)).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 5))
        file.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
    }
    func search(_ app: XCUIApplication, for title: String) {
        let field = app.textFields["librarySearch"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        field.tap()
        if let value = field.value as? String, value != field.placeholderValue { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)) }
        field.typeText(title)
    }
    func testPDFImport() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.karloss.NativeTTSBenchmark")
        app.launch()
        XCTAssertTrue(app.buttons["addToLibrary"].waitForExistence(timeout: 10))
        chooseFixture(app, kind: "PDF", stem: "embedded")
        XCTAssertTrue(app.buttons["Import"].waitForExistence(timeout: 10))
        snapshot("PDF options")
        app.buttons["Page range"].tap()
        let from = app.textFields["1"]
        XCTAssertTrue(from.isEnabled)
        app.buttons.containing(.staticText, identifier: "All pages").firstMatch.tap()
        XCTAssertFalse(from.isEnabled)
        XCTAssertTrue(app.buttons["Import"].isEnabled)
        app.buttons["Page range"].tap()
        XCTAssertTrue(from.isEnabled)
        from.tap(); from.typeText(XCUIKeyboardKey.delete.rawValue + "0")
        XCTAssertFalse(app.buttons["Import"].isEnabled)
        from.typeText(XCUIKeyboardKey.delete.rawValue + "2")
        from.tap(); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.buttons["Import"].tap()
        search(app, for: "embedded")
        XCTAssertTrue(app.staticTexts["embedded"].firstMatch.waitForExistence(timeout: 5))
        app.staticTexts["embedded"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Embedded page 2")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Embedded page 1")).firstMatch.exists)
        snapshot("PDF Reader")
        app.sliders["Document position"].adjust(toNormalizedSliderPosition: 1)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Page 3 of 3")).firstMatch.waitForExistence(timeout: 3))
        app.buttons["Document navigation"].tap()
        XCTAssertTrue(app.buttons["Page 2"].waitForExistence(timeout: 3)); app.buttons["Page 2"].tap()
        app.buttons["Document actions"].tap(); app.buttons["Export Text…"].tap()
        XCTAssertTrue(app.buttons["DOCPicker.actionButton"].waitForExistence(timeout: 5))
        app.buttons["DOCPicker.actionButton"].tap()
        XCTAssertTrue(app.buttons["DOCPicker.actionButton"].waitForNonExistence(timeout: 5))
    }
    func testEPUBImport() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.karloss.NativeTTSBenchmark")
        app.launch()
        chooseFixture(app, kind: "EPUB", stem: "chapters")
        XCTAssertTrue(app.buttons["Import"].waitForExistence(timeout: 15))
        snapshot("EPUB chapters")
        app.buttons["Two"].tap()
        app.buttons["Import"].tap()
        search(app, for: "Fixture EPUB")
        app.staticTexts["Fixture EPUB"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "FIRST chapter")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "SECOND chapter")).firstMatch.exists)
        app.buttons["Document navigation"].tap()
        XCTAssertTrue(app.buttons["Three"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Two"].exists)
        app.buttons["Three"].tap()
        snapshot("EPUB selected chapters Reader")
        app.buttons["Document actions"].tap(); app.buttons["Export Text…"].tap()
        XCTAssertTrue(app.buttons["DOCPicker.actionButton"].waitForExistence(timeout: 5))
        app.buttons["DOCPicker.actionButton"].tap()
        XCTAssertTrue(app.buttons["DOCPicker.actionButton"].waitForNonExistence(timeout: 5))
    }
    func testNoTOCAndImportError() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.karloss.NativeTTSBenchmark")
        app.launch()
        chooseFixture(app, kind: "EPUB", stem: "no-toc")
        XCTAssertTrue(app.staticTexts["No usable table of contents. Showing sections in reading order."].waitForExistence(timeout: 15))
        snapshot("EPUB without TOC")
        app.buttons["Import"].tap()
        search(app, for: "No TOC Fixture")
        app.staticTexts["No TOC Fixture"].firstMatch.tap()
        XCTAssertTrue(app.buttons["readerPlayPause"].waitForExistence(timeout: 5))
        app.buttons["Document navigation"].tap()
        XCTAssertTrue(app.buttons["Section 2"].waitForExistence(timeout: 3))
        app.buttons["Section 2"].tap()
        snapshot("EPUB no TOC Reader")
        app.navigationBars.buttons["Library"].tap()
        chooseFixture(app, kind: "PDF", stem: "corrupt")
        XCTAssertTrue(app.alerts["Import could not finish"].waitForExistence(timeout: 10))
        snapshot("Corrupt PDF error")
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "Add text").firstMatch.waitForExistence(timeout: 3))
        app.buttons["Close"].tap()
        search(app, for: "corrupt")
        XCTAssertFalse(app.staticTexts["corrupt"].exists)
    }
    func testEPUBSelectAll() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.karloss.NativeTTSBenchmark")
        app.launch()
        chooseFixture(app, kind: "EPUB", stem: "selection")
        XCTAssertTrue(app.buttons["Import"].waitForExistence(timeout: 15))
        let all = app.buttons["All chapters"]
        XCTAssertTrue(all.isSelected)
        for name in ["One", "Two", "Three"] { XCTAssertTrue(app.buttons[name].isSelected) }
        all.tap()
        XCTAssertFalse(all.isSelected)
        for name in ["One", "Two", "Three"] { XCTAssertFalse(app.buttons[name].isSelected) }
        XCTAssertFalse(app.buttons["Import"].isEnabled)
        app.buttons["One"].tap()
        XCTAssertTrue(app.buttons["One"].isSelected)
        XCTAssertFalse(all.isSelected)
        XCTAssertTrue(app.buttons["Import"].isEnabled)
        all.tap()
        XCTAssertTrue(all.isSelected)
        for name in ["One", "Two", "Three"] { XCTAssertTrue(app.buttons[name].isSelected) }
        app.buttons["One"].tap(); app.buttons["Three"].tap()
        XCTAssertFalse(all.isSelected)
        XCTAssertTrue(app.buttons["Two"].isSelected)
        XCTAssertTrue(app.buttons["Import"].isEnabled)
        snapshot("Only chapter Two selected")
        app.buttons["Import"].tap()
        search(app, for: "All Chapters Fixture")
        app.staticTexts["All Chapters Fixture"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "SECOND chapter")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Document actions"].tap(); app.buttons["Export Text…"].tap()
        XCTAssertTrue(app.buttons["DOCPicker.actionButton"].waitForExistence(timeout: 5))
        app.buttons["DOCPicker.actionButton"].tap()
        XCTAssertTrue(app.buttons["DOCPicker.actionButton"].waitForNonExistence(timeout: 5))
    }

    func testCancellation() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.karloss.NativeTTSBenchmark")
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        chooseFixture(app, kind: "PDF", stem: "cancel")
        XCTAssertTrue(app.buttons["Import"].waitForExistence(timeout: 10))
        app.buttons["Import"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        snapshot("Processing before Cancel")
        app.buttons["Cancel"].tap()
        search(app, for: "cancel")
        XCTAssertFalse(app.staticTexts["cancel"].exists)
        app.terminate(); app.launch()
        search(app, for: "cancel")
        XCTAssertFalse(app.staticTexts["cancel"].exists)
    }
    func testMixedPDFAllPages() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.karloss.NativeTTSBenchmark")
        app.launch()
        chooseFixture(app, kind: "PDF", stem: "mixed")
        XCTAssertTrue(app.buttons["Import"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["1"].isEnabled)
        app.buttons["Import"].tap()
        search(app, for: "mixed")
        app.staticTexts["mixed"].firstMatch.tap()
        XCTAssertTrue(app.buttons["readerPlayPause"].waitForExistence(timeout: 5))
        app.buttons["Document navigation"].tap()
        XCTAssertTrue(app.buttons["Page 2"].waitForExistence(timeout: 5))
        app.buttons["Page 2"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Page 2 of 2")).firstMatch.waitForExistence(timeout: 3))
        snapshot("Mixed PDF OCR Reader")
        app.buttons["Document actions"].tap(); app.buttons["Export Text…"].tap()
        XCTAssertTrue(app.buttons["DOCPicker.actionButton"].waitForExistence(timeout: 5))
        app.buttons["DOCPicker.actionButton"].tap()
        XCTAssertTrue(app.buttons["DOCPicker.actionButton"].waitForNonExistence(timeout: 5))
    }
    func testPhotoImport() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.karloss.NativeTTSBenchmark")
        app.launch()
        app.buttons["addToLibrary"].tap()
        app.buttons.containing(.staticText, identifier: "Choose photos").firstMatch.tap()
        let images = app.images.matching(identifier: "PXGGridLayout-Info")
        XCTAssertTrue(images.element(boundBy: 1).waitForExistence(timeout: 30))
        snapshot("Photos picker before selection")
        // Fresh validation simulator: newest fixtures are SECOND then FIRST in the grid.
        images.element(boundBy: 1).tap()
        images.element(boundBy: 0).tap()
        snapshot("Photos ordered selection")
        app.buttons["Done"].tap()
        search(app, for: "Photos ·")
        let title = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Photos ·")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10)); title.tap()
        XCTAssertTrue(app.buttons["readerPlayPause"].waitForExistence(timeout: 10))
        snapshot("Photos Reader")
        app.buttons["Document navigation"].tap()
        XCTAssertTrue(app.buttons["Page 2"].waitForExistence(timeout: 5)); app.buttons["Page 2"].tap()
        app.buttons["Document actions"].tap(); app.buttons["Export Text…"].tap()
        XCTAssertTrue(app.buttons["DOCPicker.actionButton"].waitForExistence(timeout: 5))
        app.buttons["DOCPicker.actionButton"].tap()
        XCTAssertTrue(app.buttons["DOCPicker.actionButton"].waitForNonExistence(timeout: 5))
    }
    func testLargeTextLayout() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.karloss.NativeTTSBenchmark")
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["addToLibrary"].waitForExistence(timeout: 10))
        snapshot("Library largest Dynamic Type")
        let document = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "% complete")).firstMatch
        XCTAssertTrue(document.waitForExistence(timeout: 5)); document.tap()
        XCTAssertTrue(app.buttons["readerPlayPause"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["readerPlayPause"].isHittable)
        XCTAssertTrue(app.buttons["Next sentence"].isHittable)
        app.buttons["Next sentence"].tap()
        app.buttons["Previous sentence"].tap()
        snapshot("Reader largest Dynamic Type")
        app.navigationBars.buttons["Library"].tap()
        app.buttons["Settings"].firstMatch.tap()
        snapshot("Settings largest Dynamic Type")
    }
    func testTextReaderAndSettings() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.karloss.NativeTTSBenchmark")
        app.launch()
        XCTAssertTrue(app.buttons["addToLibrary"].waitForExistence(timeout: 15))
        snapshot("Library")
        app.buttons["addToLibrary"].tap()
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "Add text").firstMatch.waitForExistence(timeout: 5))
        snapshot("Add to Library")
        app.buttons.containing(.staticText, identifier: "Add text").firstMatch.tap()
        let title = "UI anatomy \(Int(Date().timeIntervalSince1970))"
        app.textFields["textTitle"].tap(); app.textFields["textTitle"].typeText(title)
        app.textViews["textContent"].tap()
        app.textViews["textContent"].typeText("La fisioterapia estudia el movimiento y la contracción muscular. La articulación glenohumeral permite mover el brazo.\n\nLa apófisis coracoides es una referencia anatómica. El esternocleidomastoideo participa en el movimiento del cuello.")
        app.buttons["saveText"].tap()
        XCTAssertTrue(app.textFields["librarySearch"].waitForExistence(timeout: 10))
        // Prior validation documents may put a new unopened row outside LazyVStack's viewport.
        app.textFields["librarySearch"].tap(); app.textFields["librarySearch"].typeText(title)
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
        app.staticTexts[title].firstMatch.tap()
        XCTAssertTrue(app.buttons["readerPlayPause"].waitForExistence(timeout: 5))
        snapshot("Reader")
        app.buttons["Next sentence"].tap()
        XCTAssertTrue(app.staticTexts["Sentence 2 of 4"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["Next paragraph"].tap()
        XCTAssertTrue(app.staticTexts["Sentence 3 of 4"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["Previous paragraph"].tap()
        XCTAssertTrue(app.staticTexts["Sentence 1 of 4"].firstMatch.exists)
        app.buttons["Next sentence"].tap()
        app.buttons["readerPlayPause"].tap()
        XCTAssertEqual(app.buttons["readerPlayPause"].label, "Pause")
        app.buttons["readerPlayPause"].tap()
        XCTAssertEqual(app.buttons["readerPlayPause"].label, "Play")
        app.buttons["Next paragraph"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 10))
        app.staticTexts[title].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Sentence 3 of 4"].firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons["Library"].tap()
        app.textFields["librarySearch"].tap()
        app.textFields["librarySearch"].typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: title.count))
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Highlight text while reading"].waitForExistence(timeout: 5))
        snapshot("Settings")
        app.buttons["Dark"].tap(); snapshot("Settings Dark")
        app.buttons["System"].tap()
        app.buttons.containing(.staticText, identifier: "Automatic").firstMatch.tap()
        XCTAssertTrue(app.segmentedControls.buttons["Spanish"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["All"].tap(); snapshot("Voices")
        app.navigationBars.buttons["Settings"].tap()
        app.buttons["Library"].firstMatch.tap()
    }
    func testDocumentActions() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.karloss.NativeTTSBenchmark")
        app.launch()
        XCTAssertTrue(app.buttons["addToLibrary"].waitForExistence(timeout: 10))
        app.buttons["addToLibrary"].tap()
        app.buttons.containing(.staticText, identifier: "Add text").firstMatch.tap()
        let title = "Actions \(Int(Date().timeIntervalSince1970))"
        let renamed = "Renamed " + title
        app.textFields["textTitle"].tap(); app.textFields["textTitle"].typeText(title)
        app.textViews["textContent"].tap(); app.textViews["textContent"].typeText("La fisioterapia estudia el movimiento.\n\nEl sistema muscular sostiene el cuerpo.")
        app.buttons["saveText"].tap()
        XCTAssertTrue(app.textFields["librarySearch"].waitForExistence(timeout: 5))
        app.textFields["librarySearch"].tap(); app.textFields["librarySearch"].typeText(title)
        app.buttons["Actions for \(title)"].tap(); app.buttons["Rename"].tap()
        let field = app.alerts.textFields.firstMatch
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: title.count + 5))
        field.typeText(renamed)
        XCTAssertEqual(field.value as? String, renamed)
        // XCTest's synthetic typing leaves the software keyboard hidden on this
        // simulator. The next touch brings it back and moves the alert. Focus the
        // field and wait for the keyboard before resolving Save's tap location.
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        snapshot("Rename ready")
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout: 3))
        app.textFields["librarySearch"].tap()
        app.textFields["librarySearch"].typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: title.count))
        app.textFields["librarySearch"].typeText(renamed)
        XCTAssertTrue(app.staticTexts[renamed].firstMatch.waitForExistence(timeout: 3))
        app.terminate(); app.launch()
        XCTAssertTrue(app.textFields["librarySearch"].waitForExistence(timeout: 10))
        app.textFields["librarySearch"].tap(); app.textFields["librarySearch"].typeText(renamed)
        XCTAssertTrue(app.staticTexts[renamed].firstMatch.waitForExistence(timeout: 5))
        app.textFields["librarySearch"].typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: renamed.count))
        app.textFields["librarySearch"].tap(); app.textFields["librarySearch"].typeText("unmatched title")
        XCTAssertTrue(app.staticTexts["No matching documents"].waitForExistence(timeout: 3))
        snapshot("Search empty")
        app.textFields["librarySearch"].typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 15))
        app.textFields["librarySearch"].typeText(renamed)
        app.buttons["Actions for \(renamed)"].tap(); app.buttons["Export Text…"].tap()
        XCTAssertTrue(app.buttons["DOCPicker.actionButton"].waitForExistence(timeout: 5))
        snapshot("Export Text")
        app.buttons["DOCPicker.actionButton"].tap()
        XCTAssertTrue(app.buttons["DOCPicker.actionButton"].waitForNonExistence(timeout: 5))
        app.buttons["Actions for \(renamed)"].tap(); app.buttons["Delete"].tap()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts[renamed].firstMatch.waitForNonExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["addToLibrary"].waitForExistence(timeout: 10))
        app.textFields["librarySearch"].tap(); app.textFields["librarySearch"].typeText(renamed)
        XCTAssertTrue(app.staticTexts["No matching documents"].waitForExistence(timeout: 5))
    }
}
