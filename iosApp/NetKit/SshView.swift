import SwiftUI
import NetKitShared
import UniformTypeIdentifiers

private struct ProfileEdit: Identifiable {
    let id = UUID()
    let profile: SshProfile?
}

@MainActor
func sshHostPromptMessage(_ prompt: SshViewModel.HostPrompt) -> String {
    var text = "\(prompt.endpoint)\n\(prompt.algorithm)\n\(prompt.fingerprint)"
    if let previous = prompt.previousRejected {
        text += "\n\(String(localized: "ssh.host.previously.rejected"))\n\(previous)"
        if prompt.repeatedRejected { text += "\n\(String(localized: "ssh.host.rejected.again"))" }
    }
    return text
}

struct SshView: View {
    @ObservedObject var model: SshViewModel
    @State private var editing: ProfileEdit?
    @State private var showImporter = false
    @State private var showImportConfirm = false
    @State private var control = false
    @State private var followOutput = true
    @State private var keyboardReset = UUID()
    @State private var keyName = ""
    @State private var pendingPaste: String?
    @State private var showPasteConfirm = false
    @State private var resetEndpoint: String?
    @State private var showReset = false
    @State private var deleteProfile: SshProfile?
    @State private var deleteKey: SshKeyInfo?
    @State private var columns = 80
    @State private var rows = 24

    var body: some View {
        Form {
            Text("ssh.notice")
            if let error = model.error { Text(errorKey(error)).foregroundStyle(.red) }
            if let changed = model.changedHost {
                Section("ssh.host.changed.context") {
                    Text(verbatim: changed.endpoint)
                    LabeledContent("ssh.host.saved", value: changed.saved)
                    LabeledContent("ssh.host.offered", value: changed.offered)
                }
            }
            Section("ssh.profiles") {
                if let profiles = model.data?.profiles {
                    ForEach(profiles, id: \.id) { profile in
                        HStack {
                            Button(profile.name) { model.connect(profile) }.disabled(model.connected)
                            Spacer()
                            Button("ssh.edit") { editing = ProfileEdit(profile: profile) }.disabled(model.connected)
                            Button(role: .destructive) { deleteProfile = profile } label: { Image(systemName: "trash") }
                                .accessibilityLabel("ssh.profile.delete")
                        }
                    }
                    if profiles.isEmpty { Text("ssh.empty") }
                }
                Button("ssh.add") { editing = ProfileEdit(profile: nil) }
                Button("ssh.import") { showImporter = true }
            }
            Section("ssh.keys") {
                TextField("ssh.key.name", text: $keyName)
                Button("ssh.key.generate") { model.generateKey(name: keyName); keyName = "" }
                ForEach(model.data?.keys ?? [], id: \.id) { key in
                    HStack {
                        Text(verbatim: key.name)
                        Spacer()
                        Button(role: .destructive) { deleteKey = key } label: { Image(systemName: "trash") }
                            .accessibilityLabel("ssh.key.delete")
                    }
                }
                if let publicKey = model.publicKey {
                    Text(verbatim: publicKey).textSelection(.enabled)
                    Button("ssh.key.copy") { UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: publicKey]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)]) }
                }
            }
            if let keys = model.data?.hostKeys, !keys.isEmpty {
                Section("ssh.trusted") {
                    ForEach(keys, id: \.endpoint) { key in
                        Button { resetEndpoint = key.endpoint; showReset = true } label: {
                            VStack(alignment: .leading) {
                                Text(verbatim: key.endpoint)
                                LabeledContent("ssh.host.saved", value: key.fingerprint)
                                if let rejected = model.data?.rejectedHostKeys.first(where: { $0.endpoint == key.endpoint }) {
                                    LabeledContent("ssh.host.offered", value: rejected.fingerprint)
                                }
                            }
                        }
                    }
                }
            }
            Section("ssh.terminal") {
                Toggle("ssh.follow", isOn: $followOutput)
                ScrollViewReader { proxy in
                    ScrollView([.horizontal, .vertical]) {
                        if let snapshot = model.terminalSnapshot { SshTerminalRows(snapshot: snapshot) }
                    }
                    .frame(minHeight: 160, maxHeight: 300)
                    .onChange(of: model.terminalRevision) { _, _ in
                        if followOutput { proxy.scrollTo("ssh-terminal-bottom", anchor: .bottom) }
                    }
                }
                if model.connected {
                    SshKeyboard(inputEpoch: keyboardReset, onComposition: { value, marked in
                        model.composition(value, marked: marked, control: control)
                        if !marked { control = false }
                    }, onKey: { enter in sendKey(enter ? .enter : .backspace) }, onPaste: { value in
                        if model.pasteNeedsConfirmation(value) { pendingPaste = value; showPasteConfirm = true }
                        else { model.paste(value); keyboardReset = UUID() }
                    }).frame(height: 44)
                    HStack {
                        Toggle("ssh.ctrl", isOn: $control).toggleStyle(.button)
                        Button("ssh.esc") { sendKey(.escape) }
                        Button("←") { sendKey(.left) }.accessibilityLabel("ssh.left")
                        Button("↑") { sendKey(.up) }.accessibilityLabel("ssh.up")
                        Button("↓") { sendKey(.down) }.accessibilityLabel("ssh.down")
                        Button("→") { sendKey(.right) }.accessibilityLabel("ssh.right")
                    }
                    Stepper(value: $columns, in: 10...240, step: 10) { LabeledContent("ssh.columns", value: String(columns)) }
                    Stepper(value: $rows, in: 2...100, step: 2) { LabeledContent("ssh.rows", value: String(rows)) }
                    Button("ssh.resize") { model.resize(columns: columns, rows: rows) }
                    Button("ssh.copy") { model.copyTerminal() }
                    Button("ssh.disconnect") { model.disconnect() }
                }
            }
        }
        .navigationTitle("tab.ssh")
        .sheet(item: $editing) { item in
            SshProfileEditor(profile: item.profile, keys: model.data?.keys ?? []) { id, name, host, port, username, key, password in
                model.saveProfile(id: id, name: name, host: host, port: port, username: username, keyRef: key, password: password)
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { model.previewImport(url); showImportConfirm = model.importPlan != nil }
            else { model.error = .invalid }
        }
        .alert("ssh.host.first", isPresented: Binding(get: { model.hostPrompt != nil }, set: { _ in }), presenting: model.hostPrompt) { prompt in
            Button("ssh.host.accept") { model.answerHost(id: prompt.id, accept: true) }
            Button("ssh.host.reject", role: .cancel) { model.answerHost(id: prompt.id, accept: false) }
        } message: { prompt in
            Text(verbatim: sshHostPromptMessage(prompt))
        }
        .sheet(isPresented: $showImportConfirm, onDismiss: { model.importPlan = nil }) {
            NavigationStack {
                if let plan = model.importPlan {
                    List {
                        LabeledContent("ssh.import.new", value: String(model.importAddedCount(plan)))
                        LabeledContent("ssh.import.updated", value: String(plan.updatedProfiles.count))
                        LabeledContent("ssh.import.unchanged", value: String(plan.unchangedProfiles.count))
                        LabeledContent("ssh.import.skipped", value: String(plan.skipped.count))
                        ForEach(model.importChanges(plan), id: \.profileId) { change in
                            Text(verbatim: "\(change.before) → \(change.after)")
                        }
                        ForEach(Array(plan.skipped.enumerated()), id: \.offset) { _, entry in
                            Text(verbatim: entry.alias + " — " + skipReason(entry.reason.name))
                        }
                    }
                    .navigationTitle("ssh.import.preview")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("network.cancel") { showImportConfirm = false } }
                        ToolbarItem(placement: .confirmationAction) { Button("ssh.import.apply") { model.confirmImport(); showImportConfirm = false } }
                    }
                }
            }
        }
        .confirmationDialog("ssh.paste.warning", isPresented: $showPasteConfirm, titleVisibility: .visible) {
            Button("ssh.paste.confirm") { if let text = pendingPaste { model.paste(text); keyboardReset = UUID() }; pendingPaste = nil }
            Button("network.cancel", role: .cancel) { pendingPaste = nil }
        }
        .confirmationDialog("ssh.trust.reset.warning", isPresented: $showReset, titleVisibility: .visible) {
            Button("ssh.trust.reset", role: .destructive) { if let endpoint = resetEndpoint { model.resetTrust(endpoint: endpoint) }; resetEndpoint = nil }
            Button("network.cancel", role: .cancel) { resetEndpoint = nil }
        } message: {
            if let endpoint = resetEndpoint, let key = model.data?.hostKeys.first(where: { $0.endpoint == endpoint }) {
                Text(verbatim: trustResetMessage(key, rejected: model.data?.rejectedHostKeys.first(where: { $0.endpoint == endpoint })))
            }
        }
        .confirmationDialog("ssh.profile.delete.confirm", isPresented: Binding(get: { deleteProfile != nil }, set: { if !$0 { deleteProfile = nil } }), titleVisibility: .visible, presenting: deleteProfile) { profile in
            Button("ssh.profile.delete", role: .destructive) { model.deleteProfile(profile); deleteProfile = nil }
            Button("network.cancel", role: .cancel) { deleteProfile = nil }
        }
        .confirmationDialog("ssh.key.delete.confirm", isPresented: Binding(get: { deleteKey != nil }, set: { if !$0 { deleteKey = nil } }), titleVisibility: .visible, presenting: deleteKey) { key in
            Button("ssh.key.delete", role: .destructive) { model.deleteKey(key); deleteKey = nil }
            Button("network.cancel", role: .cancel) { deleteKey = nil }
        }
    }

    private func trustResetMessage(_ key: TrustedHostKey, rejected: TrustedHostKey?) -> String {
        var text = "\(key.endpoint)\n\(String(localized: "ssh.host.saved")): \(key.fingerprint)"
        if let rejected { text += "\n\(String(localized: "ssh.host.offered")): \(rejected.fingerprint)" }
        return text
    }

    private func sendKey(_ key: TerminalKey) {
        model.key(key, control: control)
        control = false
        keyboardReset = UUID()
    }

    private func skipReason(_ reason: String) -> String {
        switch reason {
        case "PROXY_JUMP": String(localized: "ssh.skip.proxyjump")
        case "PROXY_COMMAND": String(localized: "ssh.skip.proxycommand")
        case "MATCH": String(localized: "ssh.skip.match")
        case "WILDCARD": String(localized: "ssh.skip.wildcard")
        case "MISSING_HOST": String(localized: "ssh.skip.missinghost")
        default: String(localized: "ssh.skip.unsupported")
        }
    }

    private func errorKey(_ error: SshViewModel.ErrorKind) -> LocalizedStringKey {
        switch error {
        case .storage: "ssh.error.storage"
        case .invalid: "ssh.error.invalid"
        case .credentials: "ssh.error.credentials"
        case .keyInUse: "ssh.error.key.in.use"
        case .connection: "ssh.error.connection"
        case .algorithm: "ssh.error.algorithm"
        case .unsupportedCredential: "ssh.error.unsupported_credential"
        case .hostChanged: "ssh.error.host.changed"
        case .hostRejected: "ssh.error.host.rejected"
        case .timeout: "ssh.error.timeout"
        case .inputOverflow: "ssh.error.input"
        }
    }
}

private struct SshProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    let profile: SshProfile?
    let keys: [SshKeyInfo]
    let save: (String?, String, String, String, String, String?, String) -> Bool
    @State private var name: String
    @State private var host: String
    @State private var port: String
    @State private var username: String
    @State private var key: String
    @State private var password = ""
    @State private var failed = false

    init(profile: SshProfile?, keys: [SshKeyInfo], save: @escaping (String?, String, String, String, String, String?, String) -> Bool) {
        self.profile = profile; self.keys = keys; self.save = save
        _name = State(initialValue: profile?.name ?? "")
        _host = State(initialValue: profile?.host ?? "")
        _port = State(initialValue: profile.map { String($0.port) } ?? "22")
        _username = State(initialValue: profile?.username ?? "")
        _key = State(initialValue: profile?.keyRef ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("ssh.name", text: $name)
                TextField("ssh.host", text: $host).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("lan.port", text: $port).keyboardType(.numberPad)
                TextField("ssh.user", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("ssh.authentication", selection: $key) {
                    Text("ssh.password").tag("")
                    ForEach(keys, id: \.id) { Text(verbatim: $0.name).tag($0.id) }
                }
                if key.isEmpty { SecureField("ssh.password", text: $password).textContentType(.password) }
                Button("ssh.save") {
                    if save(profile?.id, name, host, port, username, key.isEmpty ? nil : key, password) {
                        password = ""; dismiss()
                    } else { failed = true }
                }
                if failed { Text("ssh.error.invalid").foregroundStyle(.red) }
            }
            .navigationTitle("ssh.profile")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("network.cancel") { password = ""; dismiss() } } }
            .onDisappear { password = "" }
        }
    }
}
