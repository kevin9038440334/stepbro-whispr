import AppKit
import Carbon

/// Pega el texto en la app que tiene el foco simulando ⌘V,
/// y después devuelve el portapapeles a como estaba.
@MainActor
enum TextInserter {
    enum Outcome {
        case pasted
        /// Falta el permiso de Accesibilidad: el texto queda en el portapapeles.
        case copiedOnly
        /// El foco está en un campo de contraseña: no se pega nada.
        case secureField
    }

    private static var pendingRestore: (saved: NSPasteboard.Snapshot, task: Task<Void, Never>)?

    static func insert(_ text: String) async -> Outcome {
        // macOS activa la "entrada segura" en los campos de contraseña.
        if IsSecureEventInputEnabled() { return .secureField }

        let pasteboard = NSPasteboard.general
        // Si aún no se ha devuelto el portapapeles del dictado anterior, lo original es lo de entonces.
        let saved = pendingRestore?.saved ?? pasteboard.snapshot()
        pendingRestore?.task.cancel()
        pendingRestore = nil

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Convención para que los gestores de portapapeles ignoren esta entrada.
        pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))

        guard Permissions.accessibilityGranted else { return .copiedOnly }

        let changeCount = pasteboard.changeCount
        postCommandV()
        // El portapapeles se devuelve aparte, con margen para apps lentas: así se puede volver a dictar ya.
        let task = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            pendingRestore = nil
            // Si otra cosa ha copiado algo entretanto, no lo pisamos.
            if pasteboard.changeCount == changeCount {
                pasteboard.restore(saved)
            }
        }
        pendingRestore = (saved, task)
        return .pasted
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}

extension NSPasteboard {
    typealias Snapshot = [[PasteboardType: Data]]

    func snapshot() -> Snapshot {
        (pasteboardItems ?? []).map { item in
            var entry: [PasteboardType: Data] = [:]
            for type in item.types {
                entry[type] = item.data(forType: type)
            }
            return entry
        }
    }

    func restore(_ snapshot: Snapshot) {
        clearContents()
        let items = snapshot.map { entry in
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: type)
            }
            return item
        }
        if !items.isEmpty {
            writeObjects(items)
        }
    }
}
