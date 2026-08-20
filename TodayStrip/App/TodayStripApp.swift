import SwiftUI

@main
struct TodayStripApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        // The app lives in the menu bar; this scene exists so ⌘, and the standard menus work.
        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
