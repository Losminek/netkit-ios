import SwiftUI
import NetworkExtension
import NetKitShared

@main
struct NetKitApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack { OverviewView() }
                .tabItem { Label("tab.overview", systemImage: "wifi") }
            NavigationStack { LanView() }
                .tabItem { Label("tab.devices", systemImage: "network") }
            NavigationStack { SshView() }
                .tabItem { Label("tab.ssh", systemImage: "terminal") }
            NavigationStack { WolView() }
                .tabItem { Label("tab.wol", systemImage: "power") }
        }
    }
}

struct OverviewView: View {
    @State private var network: NEHotspotNetwork?
    @State private var checked = false
    @State private var loading = false

    var body: some View {
        Form {
            Section("tab.wifi") {
                if let network {
                    LabeledContent("wifi.ssid", value: network.ssid)
                    LabeledContent("wifi.bssid", value: network.bssid)
                } else if checked {
                    Text("wifi.unavailable")
                } else {
                    Text("wifi.not_checked")
                }
                Button("wifi.refresh") {
                    loading = true
                    Task {
                        network = await NEHotspotNetwork.fetchCurrent()
                        checked = true
                        loading = false
                    }
                }.disabled(loading)
            }
            NavigationLink("speed.title") { SpeedView() }
            NavigationLink("tab.about") { AboutView() }
        }
        .navigationTitle("tab.overview")
    }
}

struct AboutView: View {
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"

    var body: some View {
        Form {
            Text("app.title").font(.largeTitle).bold()
            HStack {
                Text("app.version")
                Spacer()
                Text(verbatim: version).accessibilityIdentifier("appVersionValue")
            }
            .accessibilityElement(children: .contain)
            if let url = URL(string: IosAboutDomain().privacyUrl(language: Bundle.main.preferredLocalizations.first ?? "en")) {
                Link("about.privacy", destination: url)
            }
            NavigationLink("about.licenses") { OpenSourceLicensesView() }
        }
        .navigationTitle("tab.about")
    }
}

struct OpenSourceLicensesView: View {
    private let text: String? = Bundle.main.url(forResource: "OpenSourceLicenses", withExtension: "txt")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Text("about.licenses.content").font(.headline)
                Text(verbatim: text ?? String(localized: "about.licenses.unavailable"))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("about.licenses")
    }
}
