@testable import NetKit
import Foundation
import CryptoKit
import NIOSSH
import NIOCore
import NIOPosix
import NetKitShared
import XCTest

final class SshMetadataStoreTests: XCTestCase {
    func testBackgroundDeadlineUsesInjectedSleepInclusiveClock() {
        var now: Int64 = 1000
        let lifecycle = IosSshLifecycle(nowMillis: { KotlinLong(value: now) })
        lifecycle.background()
        now += 299_999
        XCTAssertFalse(lifecycle.expired())
        now += 1
        XCTAssertTrue(lifecycle.foreground())
    }

    func testProfileEndpointIsSharedCanonicalValue() throws {
        let profile = try XCTUnwrap(IosSshDomain().profile(id: "id", name: "test", host: "2001:db8::1", port: 2222,
            username: "user", authentication: .password, secretRef: nil, keyRef: nil, startupCommand: "", keepaliveSeconds: 30))
        XCTAssertEqual(profile.endpoint, "[2001:db8::1]:2222")
    }

    @MainActor
    func testRejectedHostContextAndPromptMessage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SshMetadataStore(directory: directory)
        let first = try offered()
        let other = try offered()
        try store.reject(first)
        let repeated = store.rejectionContext(first)
        XCTAssertTrue(repeated.repeated)
        XCTAssertEqual(repeated.previous?.fingerprint, first.fingerprint)
        let different = store.rejectionContext(other)
        XCTAssertFalse(different.repeated)
        XCTAssertEqual(different.previous?.fingerprint, first.fingerprint)
        let prompt = SshViewModel.HostPrompt(endpoint: first.endpoint, algorithm: first.algorithm,
            fingerprint: first.fingerprint, previousRejected: repeated.previous?.fingerprint,
            repeatedRejected: repeated.repeated, reply: { _ in })
        let message = sshHostPromptMessage(prompt)
        XCTAssertTrue(message.contains(first.endpoint))
        XCTAssertTrue(message.contains(first.fingerprint))
        XCTAssertTrue(message.contains(String(localized: "ssh.host.rejected.again")))
    }

    func testChangedHostWarningSurvivesPersistenceFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SshMetadataStore(directory: directory)
        let original = try offered()
        try store.trustUnknown(original)
        try FileManager.default.removeItem(at: directory)
        try Data(UUID().uuidString.utf8).write(to: directory)
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let reported = expectation(description: "changed host warning despite storage failure")
        let rejected = expectation(description: "validation fails closed")
        let validator = SshHostKeyValidator(endpoint: original.endpoint, store: store, onFailure: { failure in
            if case .changed = failure { reported.fulfill() }
        }) { _, _, _, _, _, reply in XCTFail("Changed host must not prompt"); reply(false) }
        let promise = group.next().makePromise(of: Void.self)
        promise.futureResult.whenComplete { result in if case .failure = result { rejected.fulfill() } }
        validator.validateHostKey(hostKey: NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()).publicKey,
                                  validationCompletePromise: promise)
        await fulfillment(of: [reported, rejected], timeout: 5)
        XCTAssertEqual(store.snapshot().hostKeys.first?.fingerprint, original.fingerprint)
    }
    func testUnsupportedAlgorithmsAreDistinguishedFromOtherFailures() {
        XCTAssertTrue(sshAlgorithmNegotiationFailure(.unknownPublicKey))
        XCTAssertTrue(sshAlgorithmNegotiationFailure(.unknownSignature))
        XCTAssertTrue(sshAlgorithmNegotiationFailure(.keyExchangeNegotiationFailure))
        XCTAssertFalse(sshAlgorithmNegotiationFailure(.tcpShutdown))
        XCTAssertFalse(sshAlgorithmNegotiationFailure(.invalidExchangeHashSignature))
        XCTAssertFalse(sshAlgorithmNegotiationFailure(.invalidHostKeyForKeyExchange))
        XCTAssertTrue(sshSupportedCredentialKey("ssh-ed25519 example"))
        XCTAssertFalse(sshSupportedCredentialKey("ssh-rsa example"))
        XCTAssertFalse(sshSupportedCredentialKey("ecdsa-sha2-nistp256 example"))
    }

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
