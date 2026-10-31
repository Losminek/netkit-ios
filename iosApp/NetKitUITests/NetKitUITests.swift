import XCTest

final class NetKitUITests: XCTestCase {
    func testEnglishLaunch() throws {
        try assertLaunch(language: "en", locale: "en_US", versionLabel: "Version", sharedLabel: "IPv4 from shared core")
    }

    func testCzechLaunch() throws {
        try assertLaunch(language: "cs", locale: "cs_CZ", versionLabel: "Verze", sharedLabel: "IPv4 ze sdíleného jádra")
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
