import AppKit

/// Escucha la tecla de dictado en todo el sistema (requiere permiso de Accesibilidad).
@MainActor
final class HotkeyMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onKeyDown: ((UInt16) -> Void)?

    private(set) var isHeld = false
    private var monitors: [Any] = []

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        isHeld = false
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            let hotkey = Preferences.hotkey
            guard event.keyCode == hotkey.keyCode else { return }
            let down = event.modifierFlags.rawValue & hotkey.deviceMask != 0
            if down, !isHeld {
                isHeld = true
                onPress?()
            } else if !down, isHeld {
                isHeld = false
                onRelease?()
            }
        case .keyDown:
            onKeyDown?(event.keyCode)
        default:
            break
        }
    }
}
