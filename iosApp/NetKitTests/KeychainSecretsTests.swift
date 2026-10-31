import Foundation
import Security
import NetKitShared
import XCTest

final class KeychainSecretsTests: XCTestCase {
    func testRoundTripUpdateDeleteAndAccessibility() throws {
        let service = "cz.netkit.ios.tests." + UUID().uuidString
        let store = KeychainSecrets(service: service)
        let id = "test-secret"
        defer { try? store.delete(id) }
        XCTAssertNil(try store.get(id))
        let first = Data(UUID().uuidString.utf8)
        let second = Data(UUID().uuidString.utf8)
        try store.put(id, secret: first)
        XCTAssertEqual(try store.get(id), first)
        try store.put(id, secret: second)
        XCTAssertEqual(try store.get(id), second)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: id,
                                    kSecReturnAttributes as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &result), errSecSuccess)
        let attributes = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(attributes[kSecAttrAccessible as String] as? String,
                       kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        try store.delete(id)
        XCTAssertNil(try store.get(id))
    }

    func testSharedSecretStoreAdapterRoundTrip() {
        let keychain = KeychainSecrets(service: "cz.netkit.ios.tests." + UUID().uuidString)
        let adapter = IosSecretStoreAdapter(backend: KeychainSecretBackend(keychain: keychain))
        let random = Array(UUID().uuidString.utf8.prefix(3))
        let input = KotlinByteArray(size: Int32(random.count))
        for (index, value) in random.enumerated() { input.set(index: Int32(index), value: Int8(bitPattern: value)) }
        defer { _ = adapter.deleteSecret(id: "temporary") }
        XCTAssertNil(adapter.putSecret(id: "temporary", secret: input))
        let read = adapter.getSecret(id: "temporary")
        XCTAssertNil(read.failure)
        XCTAssertEqual(read.bytes?.size, 3)
        XCTAssertEqual(read.bytes?.get(index: 2), Int8(bitPattern: random[2]))
        XCTAssertNil(adapter.deleteSecret(id: "temporary"))
        XCTAssertNil(adapter.getSecret(id: "temporary").bytes)
    }

    func testInvalidReferenceAndOversizeRejected() {
        let store = KeychainSecrets(service: "cz.netkit.ios.tests." + UUID().uuidString)
        XCTAssertThrowsError(try store.put("bad/ref", secret: Data(UUID().uuidString.utf8)))
        XCTAssertThrowsError(try store.put("test-secret", secret: Data(repeating: 0, count: 256 * 1024 + 1)))
    }
}
