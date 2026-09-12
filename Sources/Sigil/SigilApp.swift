import SwiftUI

@main
struct SigilApp: App {
    @State private var localization = Localization()

    var body: some Scene {
        Window("Sigil", id: "main") {
            MainView()
                .environment(localization)
        }
        .windowResizability(.contentMinSize)
    }
}
