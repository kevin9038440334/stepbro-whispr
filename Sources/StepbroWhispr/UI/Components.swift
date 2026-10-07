import AppKit
import SwiftUI

// MARK: - Tipografía

extension Font {
    /// Titulares en SF Pro negrita, como los títulos grandes de las apps de Apple.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold)
    }
}

/// Colores de marca, sacados del icono.
enum Brand {
    static let indigo = Color(red: 0.24, green: 0.30, blue: 0.95)
    static let violet = Color(red: 0.55, green: 0.30, blue: 0.93)
    static let coral = Color(red: 0.98, green: 0.45, blue: 0.55)

    static let gradient = LinearGradient(
        colors: [indigo, violet, coral],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Contenedores

/// Tarjeta suave con borde fino, sobre el cristal de la ventana.
/// El borde va encima del contenido, así que no debe aceptar clics: si no, se queda
/// con los de los controles de SwiftUI que hay dentro (como los menús).
struct SoftCard<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.045), in: .rect(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(.primary.opacity(0.08))
                    .allowsHitTesting(false)
            }
    }
}

/// Etiqueta de sección en mayúsculas pequeñas ("HOY", "DICTADO"…).
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(.secondary)
    }
}

/// Píldora de cristal con una cifra.
struct StatChip: View {
    let symbol: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Piezas

/// El logo: cinco cápsulas iguales que se solapan; donde se cruzan dos queda hueco.
/// Proporción 3:2. Se rellena con la regla par-impar: `.fill(style: FillStyle(eoFill: true))`.
struct LogoMark: Shape {
    func path(in rect: CGRect) -> Path {
        // Se centra en el hueco disponible manteniendo la proporción.
        let width = min(rect.width, rect.height * 1.5)
        let height = width / 1.5
        let origin = CGPoint(x: rect.midX - width / 2, y: rect.midY - height / 2)
        let capsule = CGSize(width: width / 3, height: height)
        var path = Path()
        for index in 0..<5 {
            let frame = CGRect(origin: CGPoint(x: origin.x + CGFloat(index) * width / 6, y: origin.y), size: capsule)
            path.addRoundedRect(in: frame, cornerSize: CGSize(width: capsule.width / 2, height: capsule.width / 2))
        }
        return path
    }
}

extension LogoMark {
    /// El logo relleno como corresponde, del color del texto.
    func filled() -> some View {
        fill(style: FillStyle(eoFill: true))
    }
}

/// Onda de barras que sigue el volumen de la voz.
struct Waveform: View {
    let levels: [Float]
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 3
    var maxHeight: CGFloat = 26

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .frame(width: barWidth, height: height(at: index))
            }
        }
        .frame(height: maxHeight)
        .animation(.easeOut(duration: 0.08), value: levels)
    }

    /// Las barras de los extremos son más bajas para que la onda quede redondeada.
    private func height(at index: Int) -> CGFloat {
        let position = (Double(index) + 0.5) / Double(levels.count)
        let envelope = sqrt(sin(.pi * position))
        return barWidth + CGFloat(levels[index]) * (maxHeight - barWidth) * envelope
    }
}

/// Tecla dibujada, para explicar los atajos.
struct Keycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 7)
            .frame(minWidth: 24, minHeight: 22)
            .background(.primary.opacity(0.08), in: .capsule)
            .overlay {
                Capsule()
                    .strokeBorder(.primary.opacity(0.15))
                    .allowsHitTesting(false)
            }
    }
}

/// Icono cuadrado de color con un símbolo blanco.
struct SettingsIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color.gradient, in: .circle)
    }
}

/// Fila de un paso de configuración.
struct SetupRow<Action: View>: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String
    let done: Bool
    @ViewBuilder var action: Action

    var body: some View {
        HStack(spacing: 14) {
            SettingsIcon(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.green)
            } else {
                action
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// Divisor fino dentro de las tarjetas.
struct CardDivider: View {
    var inset: CGFloat = 16

    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.07))
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

/// Menú desplegable con forma de cápsula de cristal (los de macOS son rectangulares).
struct CapsuleMenu<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]

    var body: some View {
        Menu {
            Picker("", selection: $selection) {
                ForEach(options, id: \.value) { option in
                    Text(option.title).tag(option.value)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            // Las opciones de un menú son interruptores con marca de seleccionado: si la página
            // pide interruptores deslizantes (`.toggleStyle(.switch)`), el menú no llega a abrirse.
            .toggleStyle(.automatic)
        } label: {
            HStack(spacing: 7) {
                Text(options.first { $0.value == selection }?.title ?? "")
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 13))
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - Páginas

/// Contenedor común de las páginas: desplazamiento, márgenes y ancho máximo.
struct PageScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                content
            }
            .padding(.horizontal, 36)
            .padding(.top, 18)
            .padding(.bottom, 36)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

struct PageHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.display(34))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 620, alignment: .leading)
            }
        }
    }
}

/// Campo de texto de una línea con forma de cápsula de cristal.
struct CapsuleField: View {
    let placeholder: String
    @Binding var text: String

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 14)
            .frame(height: 30)
            .glassEffect(.regular, in: .capsule)
    }
}

/// Aviso para listas vacías.
struct EmptyHint: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }
}

/// Botón redondo pequeño para borrar una fila.
struct DeleteButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(.primary.opacity(0.08), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help("Eliminar")
    }
}

/// Etiqueta pequeña en cápsula, para variantes y datos sueltos.
struct TagChip: View {
    let text: String
    var dimmed = false

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(dimmed ? .tertiary : .secondary)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(.primary.opacity(dimmed ? 0.035 : 0.07), in: .capsule)
    }
}

/// Fila de lista con resaltado suave al pasar el ratón y, si se da, acción al hacer clic.
struct HoverRow<Content: View>: View {
    var isSelected = false
    var action: (() -> Void)?
    @ViewBuilder var content: (_ hovering: Bool) -> Content
    @State private var hovering = false

    var body: some View {
        content(hovering)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                .primary.opacity(isSelected ? 0.08 : hovering ? 0.04 : 0),
                in: .rect(cornerRadius: 18)
            )
            .padding(4)
            .contentShape(.rect)
            .onHover { hovering = $0 }
            .modifier(TapAction(action: action))
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// Solo añade el gesto si hay acción: un gesto vacío impediría seleccionar el texto de la fila.
private struct TapAction: ViewModifier {
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content.onTapGesture(perform: action)
        } else {
            content
        }
    }
}

/// Icono de la app donde se pegó un dictado. Se busca una vez por app y se guarda.
struct AppIcon: View {
    let bundleID: String?
    let name: String?
    var size: CGFloat = 20

    var body: some View {
        if let icon = AppIconCache.icon(bundleID: bundleID, name: name) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: size * 0.75))
                .foregroundStyle(.tertiary)
                .frame(width: size, height: size)
        }
    }
}

@MainActor
enum AppIconCache {
    private static var cache: [String: NSImage?] = [:]

    static func icon(bundleID: String?, name: String?) -> NSImage? {
        let key = bundleID ?? name ?? ""
        guard !key.isEmpty else { return nil }
        if let cached = cache[key] { return cached }
        let workspace = NSWorkspace.shared
        var url = bundleID.flatMap { workspace.urlForApplication(withBundleIdentifier: $0) }
        // Dictados antiguos: solo se sabe el nombre de la app.
        if url == nil, let name {
            url = NSWorkspace.shared.runningApplications.first { $0.localizedName == name }?.bundleURL
                ?? ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
                .map { URL(fileURLWithPath: $0).appending(path: name + ".app") }
                .first { FileManager.default.fileExists(atPath: $0.path) }
        }
        let icon = url.map { workspace.icon(forFile: $0.path) }
        cache[key] = icon
        return icon
    }
}
