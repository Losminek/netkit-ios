import Foundation
import CryptoKit
import NIOSSH
import NetKitShared
import XCTest

final class SshMetadataStoreTests: XCTestCase {
    private func offered() throws -> TrustedHostKey {
        let key = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()).publicKey
        let parts = String(openSSHPublicKey: key).split(separator: " ")
        let raw = try XCTUnwrap(Data(base64Encoded: String(parts[1])))
        let fingerprint = "SHA256:" + Data(SHA256.hash(data: raw)).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return TrustedHostKey(endpoint: "[192.0.2.1]:22", algorithm: String(parts[0]),
                              publicKey: String(parts[1]), fingerprint: fingerprint)
    }

    func testFirstTrustPersistsChangedKeyRejectedAndResetIsExplicit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let first = try offered()
        let changed = try offered()
        let store = try SshMetadataStore(directory: directory)
        XCTAssertEqual(store.decision(first), .unknown)
        try store.trustUnknown(first)
        XCTAssertEqual(store.decision(first), .trusted)
        XCTAssertEqual(store.decision(changed), .changed)
        XCTAssertThrowsError(try store.trustUnknown(changed))
        try store.reject(changed)
        let reopened = try SshMetadataStore(directory: directory)
        XCTAssertEqual(reopened.decision(first), .trusted)
        XCTAssertEqual(reopened.decision(changed), .changed)
        try reopened.forget(endpoint: first.endpoint)
        XCTAssertEqual(reopened.decision(changed), .unknown)
        XCTAssertEqual(reopened.snapshot().rejectedHostKeys.count, 1)
    }

    func testCorruptMetadataFailsClosed() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("ssh.json")
        let contents = Data("invalid".utf8)
        try contents.write(to: file)
        XCTAssertThrowsError(try SshMetadataStore(directory: directory))
        XCTAssertEqual(try Data(contentsOf: file), contents)
    }
}
