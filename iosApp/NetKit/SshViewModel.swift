import CryptoKit
import Darwin
import Foundation
import NetKitShared
import NIOSSH
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class SshViewModel: ObservableObject {
    struct HostPrompt: Identifiable {
        let id = UUID()
        let endpoint: String
        let algorithm: String
        let fingerprint: String
        let previousRejected: String?
        let repeatedRejected: Bool
        let reply: (Bool) -> Void
    }
    struct ChangedHost { let endpoint: String; let saved: String; let offered: String }
    enum ErrorKind { case storage, invalid, credentials, keyInUse, connection, algorithm, unsupportedCredential, hostChanged, hostRejected, timeout, inputOverflow }
    @Published var data: SshData?
    @Published var error: ErrorKind?
    @Published var hostPrompt: HostPrompt?
    @Published var changedHost: ChangedHost?
    @Published var connected = false
    @Published var terminalSnapshot: TerminalSnapshot?
    @Published var terminalRevision = 0
    @Published var importPlan: SshImportPlan?
    @Published var publicKey: String?
    private let domain = IosSshDomain()
    private let credentialStore: IosSecretStoreAdapter
    private var store: SshMetadataStore?
    private var transport: SshSessionAdapter?
    private var terminal = IosTerminal(columns: 80, rows: 24)
    private var utf8Pending = Data()
    private var sessionID = UUID()
    private var activeProfile: SshProfile?
    private let lifecycle: IosSshLifecycle
    private var backgroundTask: Task<Void, Never>?

    init(nowMillis: @escaping () -> Int64 = { Int64(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) / 1_000_000) },
         keychain: KeychainSecrets = KeychainSecrets(), directory: URL? = nil) {
        credentialStore = IosSecretStoreAdapter(backend: KeychainSecretBackend(keychain: keychain))
        lifecycle = IosSshLifecycle(nowMillis: { KotlinLong(value: nowMillis()) })
        do {
            let store = try SshMetadataStore(directory: directory, onFreshInstall: { try keychain.deleteServiceItems() })
            self.store = store; data = store.snapshot()
            do { cleanupUnreferenced(try keychain.accountIDs()) }
            catch { self.error = .credentials }
        }
        catch { self.error = .storage }
    }

    func saveProfile(id: String?, name: String, host: String, port: String, username: String,
                     keyRef: String?, password: String) -> Bool {
        guard let store, let portNumber = Int32(port), (1...65535).contains(portNumber),
              password.utf8.count <= 256 * 1024 else { error = .invalid; return false }
        let previous = data?.profiles.first(where: { $0.id == id })
        let profileID = id ?? UUID().uuidString
        let sameEndpoint = previous?.host == host && previous?.port == portNumber && previous?.username == username
        let initialRef = sameEndpoint ? previous?.secretRef : nil
        let auth: SshAuthentication = keyRef == nil ? .password : .key
        guard let profile = domain.profile(id: profileID, name: name, host: host, port: portNumber,
                                           username: username, authentication: auth, secretRef: initialRef,
                                           keyRef: keyRef, startupCommand: previous?.startupCommand ?? "",
                                           keepaliveSeconds: previous?.keepaliveSeconds ?? 30) else { error = .invalid; return false }
        do {
            if keyRef == nil && !password.isEmpty {
                let ref = UUID().uuidString
                let bytes = toKotlin(Data(password.utf8))
                guard credentialStore.putSecret(id: ref, secret: bytes) == nil else { throw SshMetadataStore.Failure.io }
                guard let updated = domain.profile(id: profileID, name: name, host: host, port: portNumber,
                    username: username, authentication: auth, secretRef: ref, keyRef: nil,
                    startupCommand: previous?.startupCommand ?? "", keepaliveSeconds: previous?.keepaliveSeconds ?? 30) else {
                    _ = credentialStore.deleteSecret(id: ref); throw SshMetadataStore.Failure.invalid
                }
                do { try store.save(profile: profile, withCredential: updated) }
                catch { _ = credentialStore.deleteSecret(id: ref); throw error }
            } else {
                try store.save(profile: profile)
            }
            data = store.snapshot(); error = nil
            if let old = previous?.secretRef { cleanupUnreferenced([old]) }
            return true
        } catch { self.error = .storage; data = store.snapshot(); return false }
    }

    func generateKey(name: String) {
        guard let store, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 100 else { error = .invalid; return }
        let key = Curve25519.Signing.PrivateKey()
        let id = UUID().uuidString
        let publicText = String(openSSHPublicKey: NIOSSHPrivateKey(ed25519Key: key).publicKey)
        guard credentialStore.putSecret(id: id, secret: toKotlin(key.rawRepresentation)) == nil else { error = .credentials; return }
        do {
            try store.save(key: SshKeyInfo(id: id, name: name, publicKey: publicText))
            data = store.snapshot(); publicKey = publicText; error = nil
        } catch { _ = credentialStore.deleteSecret(id: id); self.error = .storage }
    }

    func connect(_ profile: SshProfile) {
        guard let store, transport == nil else { return }
        guard profile.authentication == .password || profile.authentication == .key else {
            error = .credentials; return
        }
        let reference = profile.authentication == .key ? profile.keyRef : profile.secretRef
        guard let reference else { error = .credentials; return }
        if profile.authentication == .key, let key = data?.keys.first(where: { $0.id == reference }),
           !sshSupportedCredentialKey(key.publicKey) {
            error = .unsupportedCredential; return
        }
        let found = credentialStore.getSecret(id: reference)
        guard found.failure == nil, let bytes = found.bytes else { error = .credentials; return }
        let raw = Data((0..<bytes.size).map { UInt8(bitPattern: bytes.get(index: $0)) })
        let credential: SshCredential
        if profile.authentication == .key { credential = .ed25519(raw) }
        else {
            guard let password = String(data: raw, encoding: .utf8) else { error = .credentials; return }
            credential = .password(password)
        }
        sessionID = UUID(); let id = sessionID
        error = nil; changedHost = nil; activeProfile = profile; connected = false; utf8Pending = Data()
        terminal = IosTerminal(columns: 80, rows: 24); terminalSnapshot = terminal.snapshot(); terminalRevision += 1
        let validator = SshHostKeyValidator(endpoint: profile.endpoint, store: store,
            onFailure: { [weak self] failure in
                guard let self, self.sessionID == id else { return }
                switch failure {
                case .changed: self.error = .hostChanged
                case .rejected: self.error = .hostRejected
                case .timeout: self.error = .timeout
                default: self.error = .storage
                }
            }, onChanged: { [weak self] saved, offered in
                guard let self, self.sessionID == id else { return }
                self.changedHost = ChangedHost(endpoint: saved.endpoint, saved: saved.fingerprint, offered: offered.fingerprint)
            }, prompt: { [weak self] endpoint, algorithm, fingerprint, previous, repeated, reply in
                guard let self, self.sessionID == id else { reply(false); return }
                self.hostPrompt = HostPrompt(endpoint: endpoint, algorithm: algorithm, fingerprint: fingerprint,
                                             previousRejected: previous?.fingerprint,
                                             repeatedRejected: repeated,
                                             reply: reply)
            })
        do {
            let session = try SshTransport(host: profile.host, port: Int(profile.port), username: profile.username,
                credential: credential, validator: validator,
                output: { [weak self] data in self?.receive(data, session: id) },
                state: { [weak self] state in
                    guard let self, self.sessionID == id else { return }
                    switch state {
                    case .connected: self.connected = true
                    case .failed: self.hostPrompt = nil; self.connected = false; self.transport = nil; if self.error == nil { self.error = .connection }
                    case .algorithmFailure: self.hostPrompt = nil; self.connected = false; self.transport = nil; self.error = .algorithm
                    case .closed: self.hostPrompt = nil; self.connected = false; self.transport = nil
                    }
                })
            transport = SshSessionAdapter(transport: session); session.start()
        } catch { self.error = .credentials }
    }

    func disconnect() {
        backgroundTask?.cancel(); backgroundTask = nil
        sessionID = UUID(); hostPrompt = nil; connected = false
        transport?.close(); transport = nil; activeProfile = nil
        terminal.composeClear(); utf8Pending = Data()
    }

    func background() {
        guard transport != nil else { return }
        lifecycle.background()
        backgroundTask?.cancel()
        backgroundTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000_000)
            guard !Task.isCancelled, let self, self.lifecycle.expired() else { return }
            self.disconnect()
        }
    }

    func foreground() {
        backgroundTask?.cancel(); backgroundTask = nil
        if lifecycle.foreground() { disconnect() }
    }

    func answerHost(id: UUID, accept: Bool) {
        guard let prompt = hostPrompt, prompt.id == id else { return }
        hostPrompt = nil
        prompt.reply(accept)
        if !accept { error = .hostRejected }
    }

    private func receive(_ data: Data, session: UUID) {
        guard session == sessionID else { return }
        utf8Pending.append(data)
        var decoded: String?
        var used = 0
        for suffix in 0...min(3, utf8Pending.count) {
            let count = utf8Pending.count - suffix
            if let text = String(data: utf8Pending.prefix(count), encoding: .utf8) { decoded = text; used = count; break }
        }
        if decoded == nil {
            decoded = String(decoding: utf8Pending, as: UTF8.self); used = utf8Pending.count
        }
        utf8Pending.removeFirst(used)
        if let decoded {
            let reply = terminal.feed(text: decoded)
            if !reply.isEmpty && transport?.send(text: reply) != true { error = .inputOverflow; disconnect(); return }
            let snapshot = terminal.snapshot()
            terminalSnapshot = snapshot
            terminalRevision += 1
        }
    }

    func type(_ value: String, control: Bool) {
        guard connected else { return }
        let text = terminal.textSequence(text: value, control: control, alt: false)
        if transport?.send(text: text) != true { error = .inputOverflow }
    }
    func composition(_ value: String, marked: Bool, control: Bool) {
        guard connected else { return }
        if marked { terminal.composeSet(value: value); return }
        terminal.composeCommit(value: value)
        guard let text = terminal.drainInput() else { error = .inputOverflow; return }
        if !text.isEmpty { type(text, control: control) }
    }
    func key(_ key: TerminalKey, control: Bool = false) {
        guard connected else { return }
        terminal.composeFinish()
        guard let pending = terminal.drainInput() else { error = .inputOverflow; return }
        if !pending.isEmpty && transport?.send(text: pending) != true { error = .inputOverflow; return }
        let text = terminal.keySequence(key: key, control: control, alt: false, shift: false)
        if transport?.send(text: text) != true { error = .inputOverflow }
    }
    func resize(columns: Int, rows: Int) {
        let columns = min(240, max(10, columns)); let rows = min(100, max(2, rows))
        terminal.resize(columns: Int32(columns), rows: Int32(rows))
        terminalSnapshot = terminal.snapshot()
        terminalRevision += 1
        transport?.resize(columns: Int32(columns), rows: Int32(rows))
    }
    func copyTerminal() {
        guard let snapshot = terminalSnapshot else { return }
        let text = (snapshot.history + snapshot.screen).map(\.text).joined(separator: "\n")
        let pasteboard = UIPasteboard.general
        pasteboard.setItems([[UTType.utf8PlainText.identifier: text]],
                            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])
        let changeCount = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            if pasteboard.changeCount == changeCount { pasteboard.items = [] }
        }
    }
    func paste(_ value: String) {
        guard connected else { return }
        guard let (pending, sanitized) = SshTerminalInput.preparePaste(terminal: terminal, value: value) else {
            error = .inputOverflow; return
        }
        if !pending.isEmpty && transport?.send(text: pending) != true { error = .inputOverflow; return }
        if !sanitized.isEmpty && transport?.send(text: sanitized) != true { error = .inputOverflow }
    }
    func pasteNeedsConfirmation(_ value: String) -> Bool { terminal.pasteNeedsConfirmation(text: value) }

    func resetTrust(endpoint: String) {
        guard let store else { error = .storage; return }
        disconnect()
        do { try store.forget(endpoint: endpoint); data = store.snapshot() }
        catch { self.error = .storage }
    }

    private func cleanupUnreferenced(_ candidates: [String]) {
        guard let data else { return }
        let inUse = Set(data.profiles.compactMap(\.secretRef) + data.profiles.compactMap(\.keyRef) + data.keys.map(\.id))
        for ref in Set(candidates) where !inUse.contains(ref) {
            if credentialStore.deleteSecret(id: ref) != nil { error = .credentials }
        }
    }

    func deleteProfile(_ profile: SshProfile) {
        guard let store else { error = .storage; return }
        disconnect()
        do { try store.deleteProfile(id: profile.id); data = store.snapshot(); error = nil
            if let ref = profile.secretRef { cleanupUnreferenced([ref]) }
        } catch { self.error = .storage }
    }

    func deleteKey(_ key: SshKeyInfo) {
        guard let store else { error = .storage; return }
        guard data?.profiles.contains(where: { $0.keyRef == key.id }) == false else { error = .keyInUse; return }
        do { try store.deleteKey(id: key.id); data = store.snapshot(); error = nil; cleanupUnreferenced([key.id]) }
        catch { self.error = .storage }
    }

    func previewImport(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            let raw = try handle.read(upToCount: 256 * 1024 + 1) ?? Data()
            guard let store else { throw SshMetadataStore.Failure.io }
            importPlan = try store.previewImport(raw)
        } catch { self.error = .invalid }
    }
    func importAddedCount(_ plan: SshImportPlan) -> Int32 { domain.importAddedCount(plan: plan) }
    func confirmImport() {
        guard let store, let plan = importPlan else { return }
        do { try store.applyImport(plan); data = store.snapshot(); importPlan = nil; error = nil
            cleanupUnreferenced(domain.importDetachedRefs(plan: plan)) }
        catch { self.error = .storage; importPlan = nil }
    }

    func importChanges(_ plan: SshImportPlan) -> [IosSshEndpointChange] { domain.importChangedEndpoints(plan: plan) }

    private func toKotlin(_ data: Data) -> KotlinByteArray {
        let result = KotlinByteArray(size: Int32(data.count))
        for (index, value) in data.enumerated() { result.set(index: Int32(index), value: Int8(bitPattern: value)) }
        return result
    }
}
