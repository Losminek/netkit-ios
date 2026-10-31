import XCTest

final class NetKitUITests: XCTestCase {
    func testEnglishLaunch() {
        assertLaunch(language: "en", locale: "en_US", versionLabel: "Version", sharedLabel: "IPv4 from shared core")
    }

    func testCzechLaunch() {
        assertLaunch(language: "cs", locale: "cs_CZ", versionLabel: "Verze", sharedLabel: "IPv4 ze sdíleného jádra")
    }

    private func assertLaunch(language: String, locale: String, versionLabel: String, sharedLabel: String) {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launch()
        XCTAssertTrue(app.staticTexts[versionLabel].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[sharedLabel].exists)
        XCTAssertTrue(app.staticTexts["0.1.0"].exists)
        XCTAssertTrue(app.staticTexts["192.0.2.1"].exists)
    }
}
