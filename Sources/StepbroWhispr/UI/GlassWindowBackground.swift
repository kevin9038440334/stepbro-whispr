import AppKit
import SwiftUI

/// Convierte el fondo de la ventana en una lámina de Liquid Glass:
/// el escritorio se ve difuminado a través de ella, como en el Centro de control.
struct GlassWindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSGlassEffectView {
        let glass = WindowGlassView()
        glass.style = .regular
        // Un velo cálido (claro) o grafito (oscuro) para leer bien sobre cualquier fondo.
        glass.tintColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 0.55)
                : NSColor(srgbRed: 0.99, green: 0.97, blue: 0.94, alpha: 0.55)
        }
        return glass
    }

    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {}
}

private final class WindowGlassView: NSGlassEffectView {
    /// Es solo fondo: nunca acepta clics. Si no, queda por encima de las páginas
    /// con desplazamiento y se queda con los clics de menús, interruptores y campos.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Sin fondo opaco, el cristal deja ver lo que hay detrás de la ventana.
        window?.isOpaque = false
        window?.backgroundColor = .clear
    }
}
