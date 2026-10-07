import AppKit
import SwiftUI

/// Barra flotante (como la Flow bar de Wispr): una pastilla de cristal abajo
/// en el centro que nunca roba el foco a la app donde estás escribiendo.
@MainActor
final class OverlayPanel: NSPanel {
    static let size = NSSize(width: 380, height: 110)
    /// Separación entre el borde inferior del panel y la pastilla.
    static let barInset: CGFloat = 10

    /// Tiempo que hay que dejar el ratón encima para que la barra se amplíe:
    /// al pasar de largo hacia el Dock no se abre.
    private static let hoverDelay: Duration = .milliseconds(450)

    private let state: AppState
    private var mouseMonitors: [Any] = []
    private var hoverTask: Task<Void, Never>?

    init(state: AppState) {
        self.state = state
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // Justo por debajo del Dock: si el Dock está oculto y aparece, tapa la barra.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let host = OverlayHostingView(rootView: OverlayView(state: state))
        host.sizingOptions = []
        contentView = host

        trackMouse()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.moveToActiveScreen() }
        }
        moveToActiveScreen()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Coloca el panel en la pantalla donde está el ratón.
    func moveToActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        setFrameOrigin(NSPoint(x: frame.midX - Self.size.width / 2, y: frame.minY + 4))
        orderFrontRegardless()
    }

    // MARK: - Ratón

    /// El panel solo acepta clics cuando el ratón está sobre la pastilla;
    /// el resto de su área transparente deja pasar los clics a lo que haya debajo.
    private func trackMouse() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHover() }
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.updateHover() }
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    private func updateHover() {
        let inside = hotZone.contains(NSEvent.mouseLocation)
        if ignoresMouseEvents == inside {
            ignoresMouseEvents = !inside
        }
        guard inside else {
            hoverTask?.cancel()
            hoverTask = nil
            if state.overlayHovered { state.overlayHovered = false }
            return
        }
        // Ya ampliada, o esperando a ver si el ratón se queda.
        guard !state.overlayHovered, hoverTask == nil else { return }
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: Self.hoverDelay)
            guard !Task.isCancelled, let self else { return }
            hoverTask = nil
            if hotZone.contains(NSEvent.mouseLocation) {
                state.overlayHovered = true
            }
        }
    }

    /// Zona sensible alrededor de la pastilla, en coordenadas de pantalla.
    private var hotZone: NSRect {
        let size: NSSize
        if state.overlayHovered || state.phase != .idle {
            size = NSSize(width: 280, height: 56)
        } else if UserDefaults.standard.bool(forKey: Preferences.alwaysShowBarKey) {
            size = NSSize(width: 90, height: 32)
        } else {
            return .zero
        }
        return NSRect(x: frame.midX - size.width / 2, y: frame.minY, width: size.width, height: size.height)
    }
}

/// Acepta el primer clic sin activar la app, para no quitar el foco.
private final class OverlayHostingView: NSHostingView<OverlayView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct OverlayView: View {
    let state: AppState
    @AppStorage(Preferences.alwaysShowBarKey) private var alwaysShowBar = true
    @AppStorage(Preferences.hotkeyKey) private var hotkey: Hotkey = .fn

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            if isVisible {
                bar
                    .transition(.scale(scale: 0.5, anchor: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, OverlayPanel.barInset)
        .frame(width: OverlayPanel.size.width, height: OverlayPanel.size.height)
        .animation(.spring(duration: 0.4, bounce: 0.3), value: state.phase)
        .animation(.spring(duration: 0.3, bounce: 0.2), value: state.overlayHovered)
    }

    private var isVisible: Bool {
        state.phase != .idle || alwaysShowBar
    }

    /// En reposo y sin el ratón encima, la barra es una rayita de cristal.
    private var isCompact: Bool {
        state.phase == .idle && !state.overlayHovered
    }

    private var bar: some View {
        content
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, isCompact ? 0 : 6)
            .frame(width: isCompact ? 46 : nil, height: isCompact ? 10 : 38)
            .glassEffect(glass, in: .capsule)
            .contentShape(.capsule)
    }

    private var glass: Glass {
        if case .notice(_, isError: true) = state.phase {
            return .regular.tint(.red.opacity(0.5))
        }
        return .regular.tint(.black.opacity(isCompact ? 0.3 : 0.5))
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .idle:
            if state.overlayHovered {
                Button(action: state.overlayTapped) {
                    HStack(spacing: 7) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 11))
                        Text("Haz clic o mantén \(hotkey.shortName) para dictar")
                    }
                    .padding(.horizontal, 10)
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        case .recording(let handsFree):
            HStack(spacing: 10) {
                if handsFree {
                    BarButton(symbol: "xmark", help: "Cancelar", action: state.cancel)
                }
                Waveform(levels: Array(state.levels.suffix(18)), barWidth: 2.5, spacing: 2.5, maxHeight: 18)
                    .padding(.horizontal, handsFree ? 0 : 10)
                if handsFree {
                    BarButton(symbol: "stop.fill", help: "Terminar", tint: .red, action: state.overlayTapped)
                }
            }
        case .transcribing:
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .bold))
                .symbolEffect(.variableColor.iterative)
                .padding(.horizontal, 18)
        case .polishing:
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .symbolEffect(.pulse)
                Text("Puliendo")
            }
            .padding(.horizontal, 12)
        case .notice(let message, let isError):
            HStack(spacing: 7) {
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "mic.slash")
                Text(message)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
        }
    }
}

/// Botón redondo dentro de la barra flotante.
private struct BarButton: View {
    let symbol: String
    let help: String
    var tint: Color = .white.opacity(0.2)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 26, height: 26)
                .background(tint, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
