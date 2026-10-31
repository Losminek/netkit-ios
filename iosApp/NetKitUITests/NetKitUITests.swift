import XCTest

final class NetKitUITests: XCTestCase {
    func testEnglishLaunch() throws {
        try assertLaunch(language: "en", locale: "en_US", versionLabel: "Version", sharedLabel: "IPv4 from shared core")
    }

    func testCzechLaunch() throws {
        try assertLaunch(language: "cs", locale: "cs_CZ", versionLabel: "Verze", sharedLabel: "IPv4 ze sdíleného jádra")
    }

    func testToolNavigation() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.tabBars.buttons["LAN"].tap()
        XCTAssertTrue(app.buttons["Probe TCP ports"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Wi-Fi"].tap()
        let wifiCheck = app.buttons["Check current Wi-Fi"]
        XCTAssertTrue(wifiCheck.waitForExistence(timeout: 10))
        wifiCheck.tap()
        XCTAssertTrue(app.staticTexts["Current Wi-Fi details are unavailable. The system requires the appropriate entitlement and access conditions."].waitForExistence(timeout: 10))
        app.tabBars.buttons["Speed"].tap()
        XCTAssertTrue(app.buttons["Start measurement"].waitForExistence(timeout: 10))
        if app.tabBars.buttons["Wake-on-LAN"].exists { app.tabBars.buttons["Wake-on-LAN"].tap() }
        else {
            app.tabBars.buttons["More"].tap()
            app.tables.cells["Wake-on-LAN"].tap()
        }
        XCTAssertTrue(app.buttons["Save profile"].waitForExistence(timeout: 10))
    }

    func testSshEmptyState() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        if app.tabBars.buttons["SSH"].exists { app.tabBars.buttons["SSH"].tap() }
        else { app.tabBars.buttons["More"].tap(); app.tables.cells["SSH"].tap() }
        XCTAssertTrue(app.buttons["Add profile"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No SSH profiles yet."].exists)
    }

    private func assertLaunch(language: String, locale: String, versionLabel: String, sharedLabel: String) throws {
        let expectedVersion = try XCTUnwrap(Bundle(for: NetKitUITests.self).infoDictionary?["CFBundleShortVersionString"] as? String)
        XCTAssertFalse(expectedVersion.isEmpty)
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launch()
        XCTAssertTrue(app.staticTexts[versionLabel].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[sharedLabel].exists)
        let version = app.staticTexts["appVersionValue"]
        XCTAssertTrue(version.waitForExistence(timeout: 10))
        XCTAssertEqual(version.label, expectedVersion)
        let address = app.staticTexts["sharedIPv4Value"]
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        XCTAssertEqual(address.label, "192.0.2.1")
    }
}
