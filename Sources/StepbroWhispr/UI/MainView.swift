import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case home
    case dictionary
    case snippets
    case style
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Inicio"
        case .dictionary: "Diccionario"
        case .snippets: "Atajos"
        case .style: "Estilo"
        case .settings: "Ajustes"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .dictionary: "character.book.closed"
        case .snippets: "text.badge.plus"
        case .style: "textformat"
        case .settings: "gearshape"
        }
    }
}

/// Ventana principal: una lámina de cristal con barra lateral y página.
struct MainView: View {
    let state: AppState
    // SUSURRO_PAGE permite abrir directamente una página (para las pruebas de interfaz).
    @State private var page: Page = Page(rawValue: ProcessInfo.processInfo.environment["SUSURRO_PAGE"] ?? "") ?? .home
    @AppStorage(Preferences.onboardingDoneKey) private var onboardingDone = false

    var body: some View {
        Group {
            if onboardingDone {
                content
                    .transition(.opacity)
            } else {
                OnboardingView(state: state) {
                    page = .home
                    withAnimation(.easeInOut(duration: 0.4)) { onboardingDone = true }
                }
                .transition(.opacity)
            }
        }
        .frame(minWidth: 780, minHeight: 560)
        // Ningún control rectangular: todos los botones son cápsulas.
        .buttonBorderShape(.capsule)
        .background {
            GlassWindowBackground()
                .ignoresSafeArea()
        }
    }

    private var content: some View {
        HStack(spacing: 0) {
            Sidebar(state: state, page: $page)
                .frame(width: 220)
            Rectangle()
                .fill(.primary.opacity(0.07))
                .frame(width: 1)
                .ignoresSafeArea()
            Group {
                switch page {
                case .home: HomeView(state: state)
                case .dictionary: DictionaryView(vocabulary: state.vocabulary)
                case .snippets: SnippetsView(vocabulary: state.vocabulary)
                case .style: StyleView(vocabulary: state.vocabulary)
                case .settings: SettingsView(state: state)
                }
            }
            // Al cambiar de página, la nueva entra con un leve desplazamiento en vez de aparecer de golpe.
            .id(page)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(y: 8)),
                removal: .opacity
            ))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct Sidebar: View {
    let state: AppState
    @Binding var page: Page
    @Namespace private var selection
    @AppStorage(Preferences.hotkeyKey) private var hotkey: Hotkey = .fn

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                LogoMark()
                    .filled()
                    .frame(width: 27, height: 18)
                Text("stepbro whispr")
                    .font(.display(19))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 20)

            GlassEffectContainer(spacing: 6) {
                VStack(spacing: 4) {
                    ForEach(Page.allCases) { item in
                        SidebarItem(page: item, isSelected: page == item, namespace: selection) {
                            withAnimation(.spring(duration: 0.4, bounce: 0.25)) { page = item }
                        }
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            status
                .padding(12)
        }
    }

    private var status: some View {
        HStack(spacing: 10) {
            Image(systemName: statusSymbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(state.isReady ? .primary : Color.orange)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                if state.isReady {
                    HStack(spacing: 4) {
                        Text("Mantén")
                        Keycap(label: hotkey.shortName)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                } else {
                    Text("Mira los pasos en Inicio")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .glassEffect(.regular, in: .capsule)
        .animation(.default, value: state.phase)
    }

    private var statusSymbol: String {
        switch state.phase {
        case .recording: "waveform"
        case .transcribing, .polishing: "ellipsis"
        default: state.isReady ? "checkmark" : "exclamationmark"
        }
    }

    private var statusTitle: String {
        switch state.phase {
        case .recording: "Escuchando"
        case .transcribing: "Transcribiendo"
        case .polishing: "Puliendo"
        default: state.isReady ? "Listo" : "Falta configurar"
        }
    }

}

/// Elemento de la barra lateral. La selección es una burbuja de cristal
/// que se desliza y se deforma de un elemento a otro.
private struct SidebarItem: View {
    let page: Page
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            // El cristal va aplicado al propio contenido para que se dibuje detrás de él.
            if isSelected {
                label
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .glassEffectID("selection", in: namespace)
            } else {
                label
                    .background(.primary.opacity(hovering ? 0.05 : 0), in: .capsule)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var label: some View {
        HStack(spacing: 10) {
            Image(systemName: page.symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 20)
            Text(page.title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
            Spacer()
        }
        .foregroundStyle(isSelected ? .primary : .secondary)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .contentShape(.rect)
    }
}
