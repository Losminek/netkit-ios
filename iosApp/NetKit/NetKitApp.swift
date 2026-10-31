import SwiftUI
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
            NavigationStack { AboutView() }
                .tabItem { Label("tab.about", systemImage: "info.circle") }
            NavigationStack { LanView() }
                .tabItem { Label("tab.lan", systemImage: "network") }
            NavigationStack { WifiView() }
                .tabItem { Label("tab.wifi", systemImage: "wifi") }
            NavigationStack { SpeedView() }
                .tabItem { Label("tab.speed", systemImage: "speedometer") }
            NavigationStack { WolView() }
                .tabItem { Label("tab.wol", systemImage: "power") }
        }
    }
}

struct AboutView: View {
    private let address = WolDomainKt.parseIpv4(input: "192.0.2.1")?.description ?? "—"
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"

    var body: some View {
        VStack(spacing: 16) {
            Text("app.title").font(.largeTitle).bold()
            HStack {
                Text("app.version")
                Spacer()
                Text(verbatim: version).accessibilityIdentifier("appVersionValue")
            }
            .accessibilityElement(children: .contain)
            HStack {
                Text("shared.ipv4")
                Spacer()
                Text(verbatim: address).accessibilityIdentifier("sharedIPv4Value")
            }
            .accessibilityElement(children: .contain)
        }
        .padding()
    }
}
