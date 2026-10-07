// Dibuja el icono de la app y genera Resources/AppIcon.icns y Resources/AppIcon.png
// Uso: swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 185

func render() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    // Sombra exterior suave
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Fondo grafito, como el de la barra de menús
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [
        NSColor(srgbRed: 0.20, green: 0.20, blue: 0.22, alpha: 1),
        NSColor(srgbRed: 0.05, green: 0.05, blue: 0.06, alpha: 1),
    ])!.draw(in: body, angle: -90)

    // Brillo de cristal en la parte superior
    let glow = NSBezierPath(ovalIn: NSRect(x: body.minX - 120, y: body.midY + 60, width: body.width + 240, height: 600))
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.14), NSColor.white.withAlphaComponent(0)])!
        .draw(in: glow, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Borde fino luminoso
    NSColor.white.withAlphaComponent(0.18).setStroke()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 3, dy: 3), xRadius: radius - 3, yRadius: radius - 3)
    rim.lineWidth = 6
    rim.stroke()

    // El logo, en blanco: cinco cápsulas que se solapan, con los cruces huecos (regla par-impar).
    NSColor.white.setFill()
    logo(in: NSRect(x: body.midX - 270, y: body.midY - 180, width: 540, height: 360)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// El logo de stepbro whispr en un rectángulo de proporción 3:2.
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

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let master = render()
let masterURL = iconset.appendingPathComponent("icon_512x512@2x.png")
try! master.representation(using: .png, properties: [:])!.write(to: masterURL)

for (name, size) in [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    process.arguments = ["-z", "\(size)", "\(size)", masterURL.path, "--out", iconset.appendingPathComponent("\(name).png").path]
    process.standardOutput = FileHandle.nullDevice
    try! process.run()
    process.waitUntilExit()
}

let output = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try! iconutil.run()
iconutil.waitUntilExit()
try! master.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("Resources/AppIcon.png"))
print("Icono generado: \(output.path)")
