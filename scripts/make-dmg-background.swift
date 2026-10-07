// Dibuja el fondo de la ventana del instalador (.dmg), a tamaño normal y Retina.
// Uso: swift scripts/make-dmg-background.swift <carpeta de salida>
//
// Los nombres de los iconos los pinta el Finder: en negro con el Mac en modo claro y en blanco
// en modo oscuro. Por eso el fondo es un gris medio, donde los dos se leen bien.
import AppKit

let width: CGFloat = 640
// Más alto que la ventana (400): si el Finder la abre un poco más grande, no aparece una franja blanca.
let height: CGFloat = 440
/// Centro de los iconos, en coordenadas de la ventana (desde arriba). Las mismas que en dmg-settings.py.
let appCenter = CGPoint(x: 170, y: 196)
let folderCenter = CGPoint(x: 470, y: 196)

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // De aquí en adelante, «y» se mide desde arriba, como en el Finder.
    let flip = NSAffineTransform()
    flip.translateX(by: 0, yBy: height)
    flip.scaleX(by: 1, yBy: -1)
    flip.concat()

    // Grafito medio, un poco más claro arriba.
    NSGradient(colors: [
        NSColor(srgbRed: 0.49, green: 0.49, blue: 0.52, alpha: 1),
        NSColor(srgbRed: 0.42, green: 0.42, blue: 0.45, alpha: 1),
    ])!.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 90)

    // Brillo suave arriba, como el del icono, que se desvanece sin dejar borde.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.09), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: 0, y: 0, width: width, height: 220), angle: 90)

    // Lámina de cristal detrás de los iconos y sus nombres.
    let panel = NSRect(x: 48, y: 104, width: width - 96, height: 196)
    let panelPath = NSBezierPath(roundedRect: panel, xRadius: 34, yRadius: 34)
    NSColor.white.withAlphaComponent(0.06).setFill()
    panelPath.fill()
    NSColor.white.withAlphaComponent(0.16).setStroke()
    panelPath.lineWidth = 1
    panelPath.stroke()

    // Título: el logo y el nombre.
    let titleFont = NSFont.systemFont(ofSize: 22, weight: .bold)
    let title = NSAttributedString(string: "stepbro whispr", attributes: [.font: titleFont, .foregroundColor: NSColor.white])
    let mark = NSSize(width: 30, height: 20)
    let gap: CGFloat = 10
    let titleWidth = mark.width + gap + title.size().width
    let titleX = (width - titleWidth) / 2
    NSColor.white.setFill()
    logo(in: NSRect(x: titleX, y: 40 - mark.height / 2, width: mark.width, height: mark.height)).fill()
    draw(title, at: CGPoint(x: titleX + mark.width + gap, y: 40 - title.size().height / 2))

    centered("Arrastra la app a la carpeta Aplicaciones", y: 72, size: 13, weight: .regular, alpha: 0.82)

    // Flecha entre los dos iconos.
    let arrowConfiguration = NSImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.white.withAlphaComponent(0.75)]))
    let arrow = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)!.withSymbolConfiguration(arrowConfiguration)!
    let middle = CGPoint(x: (appCenter.x + folderCenter.x) / 2, y: appCenter.y)
    arrow.draw(
        in: NSRect(x: middle.x - arrow.size.width / 2, y: middle.y - arrow.size.height / 2, width: arrow.size.width, height: arrow.size.height),
        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
    )

    // Aviso para quien la instale en otro Mac: la firma no es de Apple.
    centered("¿macOS no la deja abrir la primera vez?", y: 332, size: 11.5, weight: .semibold, alpha: 0.85)
    centered("Ajustes del Sistema › Privacidad y seguridad › Abrir igualmente", y: 350, size: 11.5, weight: .regular, alpha: 0.75)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// El logo de stepbro whispr en un rectángulo de proporción 3:2 (el mismo que en make-icon.swift).
func logo(in rect: NSRect) -> NSBezierPath {
    let path = NSBezierPath()
    path.windingRule = .evenOdd
    let capsule = NSSize(width: rect.width / 3, height: rect.height)
    for index in 0..<5 {
        let frame = NSRect(origin: NSPoint(x: rect.minX + CGFloat(index) * rect.width / 6, y: rect.minY), size: capsule)
        path.append(NSBezierPath(roundedRect: frame, xRadius: capsule.width / 2, yRadius: capsule.width / 2))
    }
    return path
}

func draw(_ text: NSAttributedString, at point: CGPoint) {
    // El texto se dibuja sin voltear: se deshace el volteo solo para él.
    NSGraphicsContext.saveGraphicsState()
    let unflip = NSAffineTransform()
    unflip.translateX(by: 0, yBy: point.y + text.size().height)
    unflip.scaleX(by: 1, yBy: -1)
    unflip.concat()
    text.draw(at: CGPoint(x: point.x, y: 0))
    NSGraphicsContext.restoreGraphicsState()
}

func centered(_ string: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat) {
    let text = NSAttributedString(string: string, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor.white.withAlphaComponent(alpha),
    ])
    draw(text, at: CGPoint(x: (width - text.size().width) / 2, y: y - text.size().height / 2))
}

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/dmg")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for (scale, name) in [(1.0, "background.png"), (2.0, "background@2x.png")] {
    let data = render(scale: CGFloat(scale)).representation(using: .png, properties: [:])!
    try data.write(to: output.appendingPathComponent(name))
}
print("Fondo listo en \(output.path)")
