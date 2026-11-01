import XCTest

final class NetKitUITests: XCTestCase {
    func testEnglishLaunch() throws {
        try assertLaunch(language: "en", locale: "en_US", overview: "Overview", about: "About", versionLabel: "Version", privacy: "Privacy policy", licenses: "Open source licenses", content: "License texts")
    }

    func testCzechLaunch() throws {
        try assertLaunch(language: "cs", locale: "cs_CZ", overview: "Přehled", about: "O aplikaci", versionLabel: "Verze", privacy: "Zásady ochrany soukromí", licenses: "Open source licence", content: "Texty licencí")
    }

    func testToolNavigation() {
        assertToolNavigation(language: "en", locale: "en_US", tabs: ["Overview", "Devices", "SSH", "WoL"],
                             tcp: "Probe TCP ports", devicesEmpty: "No results yet.", wifiCheck: "Check current Wi-Fi",
                             wifiEmpty: "Current Wi-Fi has not been checked yet.",
                             wifiUnavailable: "Current Wi-Fi details are unavailable. The system requires the appropriate entitlement and access conditions.",
                             speed: "Connection speed", speedStart: "Start measurement", wolSave: "Save profile", wolEmpty: "No devices yet.")
    }

    func testCzechToolNavigation() {
        assertToolNavigation(language: "cs", locale: "cs_CZ", tabs: ["Přehled", "Zařízení", "SSH", "WoL"],
                             tcp: "Prověřit TCP porty", devicesEmpty: "Zatím žádné výsledky.", wifiCheck: "Zjistit aktuální Wi-Fi",
                             wifiEmpty: "Aktuální Wi-Fi zatím nebyla zjištěna.",
                             wifiUnavailable: "Údaje o aktuální Wi-Fi nejsou dostupné. Systém vyžaduje příslušné oprávnění a splnění podmínek přístupu.",
                             speed: "Rychlost připojení", speedStart: "Spustit měření", wolSave: "Uložit profil", wolEmpty: "Zatím žádná zařízení.")
    }

    func testSshEmptyState() {
        assertSshEmptyState(language: "en", locale: "en_US", addProfile: "Add profile", empty: "No SSH profiles yet.")
    }

    func testCzechSshEmptyState() {
        assertSshEmptyState(language: "cs", locale: "cs_CZ", addProfile: "Přidat profil", empty: "Zatím žádné SSH profily.")
    }

    func testEnglishLanConsentAndWolWarning() {
        assertLanConsentAndWolWarning(language: "en", locale: "en_US", devices: "Devices",
            host: "Target or name", ports: "Ports", tcp: "Probe TCP ports", cancel: "Cancel",
            reason: "The range includes an address outside private, shared or link-local blocks.",
            warning: "Use only on networks you own or are authorized to use. NetKit for iOS supports only unicast on the current Wi-Fi network. If a sleeping device is absent from the ARP cache, the packet may not arrive even when sending is reported as successful.")
    }

    func testCzechLanConsentAndWolWarning() {
        assertLanConsentAndWolWarning(language: "cs", locale: "cs_CZ", devices: "Zařízení",
            host: "Cíl nebo název", ports: "Porty", tcp: "Prověřit TCP porty", cancel: "Zrušit",
            reason: "Rozsah zahrnuje adresu mimo privátní, sdílené nebo link-local bloky.",
            warning: "Používejte jen ve vlastní nebo povolené síti. iOS verze NetKitu podporuje pouze unicast v aktuální Wi-Fi síti. Pokud spící zařízení vypadne z ARP cache, paket nemusí dorazit ani po hlášení o odeslání.")
    }

    private func assertLanConsentAndWolWarning(language: String, locale: String, devices: String,
                                              host: String, ports: String, tcp: String, cancel: String,
                                              reason: String, warning: String) {
        let app = launch(language: language, locale: locale)
        let tabs = app.tabBars.firstMatch.buttons
        XCTAssertTrue(tabs[devices].waitForExistence(timeout: 10))
        tabs[devices].tap()
        let hostField = app.textFields[host]
        XCTAssertTrue(hostField.waitForExistence(timeout: 10))
        hostField.tap()
        hostField.typeText("192.0.2.1")
        let portField = app.textFields[ports]
        portField.tap()
        portField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "22")
        app.buttons[tcp].tap()
        let reasonText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", reason)).firstMatch
        XCTAssertTrue(reasonText.waitForExistence(timeout: 10))
        XCTAssertTrue(reasonText.isHittable)
        app.buttons[cancel].tap()
        tabs["WoL"].tap()
        let warningText = app.staticTexts[warning]
        XCTAssertTrue(warningText.waitForExistence(timeout: 10))
        XCTAssertTrue(warningText.isHittable)
        XCTAssertFalse(app.switches["Broadcast"].exists)
    }

    private func assertToolNavigation(language: String, locale: String, tabs: [String], tcp: String,
                                      devicesEmpty: String, wifiCheck: String, wifiEmpty: String, wifiUnavailable: String,
                                      speed: String, speedStart: String, wolSave: String, wolEmpty: String) {
        let app = launch(language: language, locale: locale)
        let buttons = app.tabBars.firstMatch.buttons
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(buttons.count, 4)
        for (index, label) in tabs.enumerated() { XCTAssertEqual(buttons.element(boundBy: index).label, label) }
        XCTAssertTrue(app.staticTexts[wifiEmpty].waitForExistence(timeout: 10))
        let check = app.buttons[wifiCheck]
        XCTAssertTrue(check.waitForExistence(timeout: 10))
        check.tap()
        XCTAssertTrue(app.staticTexts[wifiUnavailable].waitForExistence(timeout: 10))
        app.buttons[speed].tap()
        XCTAssertTrue(app.buttons[speedStart].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        buttons[tabs[1]].tap()
        XCTAssertTrue(app.buttons[tcp].waitForExistence(timeout: 10))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts[devicesEmpty].waitForExistence(timeout: 10))
        buttons[tabs[3]].tap()
        XCTAssertTrue(app.buttons[wolSave].waitForExistence(timeout: 10))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts[wolEmpty].waitForExistence(timeout: 10))
    }

    private func assertSshEmptyState(language: String, locale: String, addProfile: String, empty: String) {
        let app = launch(language: language, locale: locale)
        app.tabBars.buttons["SSH"].tap()
        XCTAssertTrue(app.buttons[addProfile].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[empty].exists)
    }

    private func launch(language: String, locale: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launch()
        return app
    }

    private func assertLaunch(language: String, locale: String, overview: String, about: String, versionLabel: String, privacy: String, licenses: String, content: String) throws {
        let expectedVersion = try XCTUnwrap(Bundle(for: NetKitUITests.self).infoDictionary?["CFBundleShortVersionString"] as? String)
        XCTAssertFalse(expectedVersion.isEmpty)
        let app = launch(language: language, locale: locale)
        XCTAssertTrue(app.tabBars.buttons[overview].waitForExistence(timeout: 10))
        app.buttons[about].tap()
        XCTAssertTrue(app.staticTexts[versionLabel].waitForExistence(timeout: 10))
        let version = app.staticTexts["appVersionValue"]
        XCTAssertTrue(version.waitForExistence(timeout: 10))
        XCTAssertEqual(version.label, expectedVersion)
        XCTAssertTrue(app.links[privacy].exists || app.buttons[privacy].exists)
        app.buttons[licenses].tap()
        XCTAssertTrue(app.staticTexts[content].waitForExistence(timeout: 10))
    }
}
