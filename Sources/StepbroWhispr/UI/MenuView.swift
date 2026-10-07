import SwiftUI

/// Menú nativo de la barra de menús.
struct MenuView: View {
    let state: AppState

    @Environment(\.openWindow) private var openWindow
    @AppStorage(Preferences.hotkeyKey) private var hotkey: Hotkey = .fn

    var body: some View {
        Text(state.isReady ? "Mantén \(hotkey.shortName) para dictar" : "Falta configurar stepbro whispr")

        Button("Abrir stepbro whispr…") {
            openWindow(id: MainView.windowID)
            NSApp.activate()
        }
        .keyboardShortcut("o")

        if !state.history.items.isEmpty {
            Divider()
            Section("Copiar un dictado reciente") {
                ForEach(state.history.items.prefix(5)) { dictation in
                    Button(dictation.text.truncated(to: 48)) { state.history.copy(dictation) }
                }
            }
        }

        Divider()
        Button("Salir de stepbro whispr") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

private extension String {
    func truncated(to length: Int) -> String {
        count > length ? String(prefix(length)).trimmingCharacters(in: .whitespaces) + "…" : self
    }
}
