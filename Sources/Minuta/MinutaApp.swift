import SwiftUI

@main
struct MinutaApp: App {
    @StateObject private var model = AppModel()

    init() {
        if CLI.requested() {
            Task {
                let code = await CLI.run()
                exit(code)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.iconName)
        }

        Window("Configurações do minuta", id: "settings") {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
    }
}
