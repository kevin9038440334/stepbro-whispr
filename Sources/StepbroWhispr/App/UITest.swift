import AppKit
@preconcurrency import ApplicationServices

/// Prueba de interfaz: `SUSURRO_UITEST=/ruta/informe.txt` (con `SUSURRO_PAGE=settings`)
/// busca los menús desplegables con Accesibilidad, hace un clic real en uno y
/// comprueba si se abre su menú. Sirve para diagnosticar controles que no responden.
enum UITest {
    @MainActor private static var checked: AXUIElement?

    @MainActor
    private static func value(of element: AXUIElement) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success, let value else { return "-" }
        return "\(value)"
    }

    @MainActor
    static func runIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["SUSURRO_UITEST"] else { return }
        let target = ProcessInfo.processInfo.environment["SUSURRO_UITEST_TARGET"]
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            NSApp.activate()
            NSApp.windows.first { $0.isVisible && $0.frame.width > 500 }?.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .seconds(0.8))
            // Accesibilidad dentro del propio proceso: siempre en el hilo principal,
            // porque SwiftUI responde evaluando las vistas en el hilo que pregunta.
            if ProcessInfo.processInfo.environment["SUSURRO_UITEST_ALL"] != nil {
                runAll(path: path)
                return
            }
            var (lines, point) = scan(target: target)
            guard let point else {
                try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
                return
            }
            let pid = getpid()
            let window = NSApp.windows.first { $0.isVisible && $0.frame.width > 500 }
            // Un punto neutro (el título de la página) para activar la ventana antes del clic de verdad.
            let neutral: CGPoint? = window.map { window in
                let screenHeight = NSScreen.screens.first?.frame.height ?? 0
                return CGPoint(x: window.frame.minX + 300, y: screenHeight - window.frame.maxY + 60)
            }
            lines.append("app activa: \(NSApp.isActive), ventana principal: \(window?.isKeyWindow ?? false)")
            let before = menuWindows(of: pid)
            // El clic y la espera, fuera del hilo principal para que la app pueda abrir el menú.
            let found = lines
            Thread.detachNewThread {
                var lines = found
                if let neutral {
                    click(at: neutral)
                    Thread.sleep(forTimeInterval: 0.6)
                }
                click(at: point)
                Thread.sleep(forTimeInterval: 0.8)
                let after = menuWindows(of: pid)
                lines.append(after > before
                    ? "RESULTADO: el menú SÍ se abrió (\(after) ventanas de menú)"
                    : "RESULTADO: el menú NO se abrió")
                DispatchQueue.main.sync {
                    lines.append("valor después: \(checked.map(value(of:)) ?? "-")")
                }
                key(53)
                try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
    }

    @MainActor
    private static func runAll(path: String) {
        let app = AXUIElementCreateApplication(getpid())
        var found: [(element: AXUIElement, role: String, title: String, frame: CGRect)] = []
        collect(app, depth: 0, into: &found)
        let menus = found.filter { ["AXPopUpButton", "AXMenuButton"].contains($0.role) && $0.frame.width > 10 }
        let pid = getpid()
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let window = NSApp.windows.first { $0.isVisible && $0.frame.width > 500 }
        let windowTop = Int(screenHeight - (window?.frame.maxY ?? 0))
        let windowBottom = Int(screenHeight - (window?.frame.minY ?? 0))
        let neutral = window.map { CGPoint(x: $0.frame.minX + 300, y: screenHeight - $0.frame.maxY + 60) }
        Thread.detachNewThread {
            var lines = ["menús: \(menus.count) · ventana visible de y=\(windowTop) a y=\(windowBottom)"]
            // Primer clic en una zona neutra: activa la ventana (macOS no lo pasa a los controles).
            if let neutral {
                click(at: neutral)
                Thread.sleep(forTimeInterval: 0.6)
            }
            for menu in menus {
                // Igual que la prueba individual: activar la ventana, esperar, clic y comprobar.
                if let neutral {
                    click(at: neutral)
                    Thread.sleep(forTimeInterval: 0.6)
                }
                let before = menuWindows(of: pid)
                click(at: CGPoint(x: menu.frame.midX, y: menu.frame.midY))
                Thread.sleep(forTimeInterval: 1.0)
                let opened = menuWindows(of: pid) > before
                lines.append("\(opened ? "SE ABRE   " : "NO SE ABRE") \(menu.role) «\(menu.title)» (y=\(Int(menu.frame.midY)))")
                key(53)
                Thread.sleep(forTimeInterval: 1.0)
            }
            try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    @MainActor
    private static func scan(target: String?) -> ([String], CGPoint?) {
        var lines: [String] = []
        let app = AXUIElementCreateApplication(getpid())
        var found: [(element: AXUIElement, role: String, title: String, frame: CGRect)] = []
        collect(app, depth: 0, into: &found)
        lines.append("controles encontrados: \(found.count)")
        for item in found where item.frame.width > 20 {
            let center = CGPoint(x: item.frame.midX, y: item.frame.midY)
            lines.append("  \(item.role) «\(item.title)» → bajo el ratón: \(hitTest(app, at: center))")
        }
        let role = ProcessInfo.processInfo.environment["SUSURRO_UITEST_ROLE"]
        let candidates = found.filter { role == nil ? ["AXPopUpButton", "AXMenuButton"].contains($0.role) : $0.role == role }
        guard let chosen = candidates.first(where: { target == nil || $0.title.contains(target!) }) ?? candidates.first else {
            lines.append("no hay ningún menú desplegable")
            return (lines, nil)
        }
        let point = CGPoint(x: chosen.frame.midX, y: chosen.frame.midY)
        lines.append("clic en: \(chosen.role) «\(chosen.title)» valor antes: \(value(of: chosen.element))")
        checked = chosen.element
        lines.append("bajo el ratón: \(hitTest(app, at: point))")
        return (lines, point)
    }

    private static func collect(_ element: AXUIElement, depth: Int, into found: inout [(element: AXUIElement, role: String, title: String, frame: CGRect)]) {
        guard depth < 40 else { return }
        let role = string(element, kAXRoleAttribute) ?? ""
        if ["AXPopUpButton", "AXMenuButton", "AXButton", "AXCheckBox"].contains(role) {
            let title = string(element, kAXTitleAttribute) ?? string(element, kAXDescriptionAttribute) ?? string(element, kAXValueAttribute) ?? ""
            found.append((element, role, title, frame(of: element)))
        }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let list = children as? [AXUIElement]
        else { return }
        for child in list {
            collect(child, depth: depth + 1, into: &found)
        }
    }

    private static func hitTest(_ app: AXUIElement, at point: CGPoint) -> String {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &element) == .success, var current = element else {
            return "nada"
        }
        // Describe el elemento y sus padres hasta la ventana.
        var chain: [String] = []
        for _ in 0..<8 {
            let role = string(current, kAXRoleAttribute) ?? "?"
            let id = string(current, kAXIdentifierAttribute) ?? ""
            let subrole = string(current, kAXSubroleAttribute) ?? ""
            let box = frame(of: current)
            var children: CFTypeRef?
            AXUIElementCopyAttributeValue(current, kAXChildrenAttribute as CFString, &children)
            let count = (children as? [AXUIElement])?.count ?? 0
            chain.append("\(role)\(subrole.isEmpty ? "" : "/\(subrole)")\(id.isEmpty ? "" : "#\(id)") \(Int(box.width))x\(Int(box.height)) hijos:\(count)")
            if role == "AXWindow" { break }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success, let parent else { break }
            current = parent as! AXUIElement
        }
        return chain.joined(separator: " ⟵ ")
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func frame(of element: AXUIElement) -> CGRect {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        var position = CGPoint.zero
        var size = CGSize.zero
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
           let positionValue {
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        }
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
           let sizeValue {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        }
        return CGRect(origin: position, size: size)
    }

    private static func menuWindows(of pid: pid_t) -> Int {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.filter {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid
                && ($0[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.popUpMenuWindow))
        }.count
    }

    private static func click(at point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.08)
        }
    }

    private static func key(_ code: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)?.post(tap: .cghidEventTap)
        }
    }
}
