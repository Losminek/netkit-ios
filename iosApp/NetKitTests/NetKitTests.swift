import XCTest
import NetKitShared

final class NetKitTests: XCTestCase {
    func testSharedIpv4Parser() {
        XCTAssertEqual(WolDomainKt.parseIpv4(input: "192.0.2.1")?.description, "192.0.2.1")
        XCTAssertNil(WolDomainKt.parseIpv4(input: "192.0.2.256"))
    }
}
