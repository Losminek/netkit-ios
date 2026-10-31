import XCTest

final class NetKitUITests: XCTestCase {
    func testEnglishLaunch() throws {
        try assertLaunch(language: "en", locale: "en_US", versionLabel: "Version", sharedLabel: "IPv4 from shared core")
    }

    func testCzechLaunch() throws {
        try assertLaunch(language: "cs", locale: "cs_CZ", versionLabel: "Verze", sharedLabel: "IPv4 ze sdíleného jádra")
    }

    func testToolNavigation() {
        assertToolNavigation(language: "en", locale: "en_US", about: "About", speed: "Speed",
                             wol: "Wake-on-LAN", tcp: "Probe TCP ports", wifiCheck: "Check current Wi-Fi",
                             wifiUnavailable: "Current Wi-Fi details are unavailable. The system requires the appropriate entitlement and access conditions.",
                             speedStart: "Start measurement", wolSave: "Save profile")
    }

    func testCzechToolNavigation() {
        assertToolNavigation(language: "cs", locale: "cs_CZ", about: "O aplikaci", speed: "Rychlost",
                             wol: "Probuzení", tcp: "Prověřit TCP porty", wifiCheck: "Zjistit aktuální Wi-Fi",
                             wifiUnavailable: "Údaje o aktuální Wi-Fi nejsou dostupné. Systém vyžaduje příslušné oprávnění a splnění podmínek přístupu.",
                             speedStart: "Spustit měření", wolSave: "Uložit profil")
    }

    func testSshEmptyState() {
        assertSshEmptyState(language: "en", locale: "en_US", about: "About", speed: "Speed",
                            addProfile: "Add profile", empty: "No SSH profiles yet.")
    }

    func testCzechSshEmptyState() {
        assertSshEmptyState(language: "cs", locale: "cs_CZ", about: "O aplikaci", speed: "Rychlost",
                            addProfile: "Přidat profil", empty: "Zatím žádné SSH profily.")
    }

    private func assertToolNavigation(language: String, locale: String, about: String, speed: String,
                                      wol: String, tcp: String, wifiCheck: String, wifiUnavailable: String,
                                      speedStart: String, wolSave: String) {
        let app = launch(language: language, locale: locale)
        app.tabBars.buttons["LAN"].tap()
        XCTAssertTrue(app.buttons[tcp].waitForExistence(timeout: 10))
        app.tabBars.buttons["Wi-Fi"].tap()
        let check = app.buttons[wifiCheck]
        XCTAssertTrue(check.waitForExistence(timeout: 10))
        check.tap()
        XCTAssertTrue(app.staticTexts[wifiUnavailable].waitForExistence(timeout: 10))
        app.tabBars.buttons[speed].tap()
        XCTAssertTrue(app.buttons[speedStart].waitForExistence(timeout: 10))
        openTab(wol, in: app, about: about, speed: speed)
        XCTAssertTrue(app.buttons[wolSave].waitForExistence(timeout: 10))
    }

    private func assertSshEmptyState(language: String, locale: String, about: String, speed: String,
                                     addProfile: String, empty: String) {
        let app = launch(language: language, locale: locale)
        openTab("SSH", in: app, about: about, speed: speed)
        XCTAssertTrue(app.buttons[addProfile].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[empty].exists)
    }

    private func launch(language: String, locale: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launch()
        return app
    }

    private func openTab(_ label: String, in app: XCUIApplication, about: String, speed: String) {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        let direct = app.tabBars.buttons[label]
        if direct.exists { direct.tap(); return }
        let buttons = app.tabBars.buttons
        XCTAssertEqual(buttons.count, 5)
        for required in [about, "LAN", "Wi-Fi", speed] { XCTAssertTrue(buttons[required].exists) }
        let more = buttons.element(boundBy: 4)
        XCTAssertTrue(more.exists)
        XCTAssertFalse(more.label.isEmpty)
        XCTAssertFalse([about, "LAN", "Wi-Fi", speed].contains(more.label))
        more.tap()
        let item = app.staticTexts[label]
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        item.tap()
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
