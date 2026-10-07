import SwiftUI

@main
struct StepbroWhisprApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(Preferences.showInMenuBarKey) private var showInMenuBar = true

    var body: some Scene {
        Window("stepbro whispr", id: MainView.windowID) {
            MainView(state: appDelegate.state)
        }
        .defaultSize(width: 980, height: 720)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)

        MenuBarExtra(isInserted: $showInMenuBar) {
            MenuView(state: appDelegate.state)
        } label: {
            Image(systemName: appDelegate.state.menuBarSymbol)
        }
    }
}

extension MainView {
    static let windowID = "main"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    private var overlay: OverlayPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let overlay = OverlayPanel(state: state)
        state.onOverlayWillAppear = { [weak overlay] in overlay?.moveToActiveScreen() }
        self.overlay = overlay
        state.launch()
    }

    /// Cerrar la ventana no cierra la app: el dictado sigue funcionando.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
