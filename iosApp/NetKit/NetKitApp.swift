import SwiftUI
import NetKitShared

@main
struct NetKitApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
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
