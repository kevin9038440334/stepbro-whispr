import ApplicationServices
import Foundation

/// Lee lo que ya hay escrito antes del cursor en la app donde se va a dictar,
/// para continuar la frase y escribir los nombres igual. Usa el permiso de Accesibilidad.
enum FocusContext {
    /// Las terminales exponen toda la pantalla como texto: lo de antes del cursor no es una frase.
    private static let skippedApps: Set<String> = [
        "com.apple.terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.warp-stable",
        "com.stepbro.terminal", "net.kovidgoyal.kitty", "co.zeit.hyper", "org.alacritty",
    ]

    private static let textRoles: Set<String> = [
        kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String, "AXSearchField",
    ]

    /// Hasta `limit` caracteres de antes del cursor, o nil si la app no deja leerlos.
    /// Bloquea como mucho unas décimas: se llama fuera del hilo principal.
    nonisolated static func textBeforeCursor(bundleID: String?, limit: Int = 600) -> String? {
        guard AXIsProcessTrusted(), let bundleID, !skippedApps.contains(bundleID.lowercased()) else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        guard let focused = copy(system, kAXFocusedUIElementAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return nil
        }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.2)
        // Solo campos de texto de verdad: en una página web entera, «antes del cursor» no significa nada.
        guard let role = copy(element, kAXRoleAttribute) as? String, textRoles.contains(role) else { return nil }
        // Nunca se lee un campo de contraseña.
        if let subrole = copy(element, kAXSubroleAttribute) as? String, subrole == (kAXSecureTextFieldSubrole as String) {
            return nil
        }
        guard let rangeValue = copy(element, kAXSelectedTextRangeAttribute), CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            return nil
        }
        var selection = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &selection), selection.location > 0 else { return nil }

        var wanted = CFRange(location: max(0, selection.location - limit), length: min(limit, selection.location))
        if let axRange = AXValueCreate(.cfRange, &wanted) {
            var result: CFTypeRef?
            let status = AXUIElementCopyParameterizedAttributeValue(
                element, kAXStringForRangeParameterizedAttribute as CFString, axRange, &result
            )
            if status == .success, let text = result as? String { return text }
        }
        // Algunas apps solo dan el texto entero.
        guard let whole = copy(element, kAXValueAttribute) as? String else { return nil }
        let text = whole as NSString
        guard selection.location <= text.length else { return nil }
        return text.substring(with: NSRange(location: wanted.location, length: wanted.length))
    }

    nonisolated private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }
}
