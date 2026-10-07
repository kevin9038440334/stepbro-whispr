import StepbroWhisprCore
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case name
    case microphone
    case accessibility
    case hotkey
    case language
    case tryIt
}

/// Bienvenida paso a paso: nombre, permisos, tecla, idioma y una prueba.
struct OnboardingView: View {
    let state: AppState
    let onFinish: () -> Void

    @State private var step: OnboardingStep = .welcome
    @State private var forward = true
    @State private var sample = ""
    @State private var lastDictationID: UUID?
    @Namespace private var glassNamespace
    @State private var logoShown = false

    @AppStorage(Preferences.userNameKey) private var userName = ""
    @AppStorage(Preferences.hotkeyKey) private var hotkey: Hotkey = .fn
    @AppStorage(Preferences.languageKey) private var language = ""
    @AppStorage(Preferences.polishKey) private var polish = true

    var body: some View {
        VStack(spacing: 0) {
            progress
                .padding(.top, 34)
                .opacity(step == .welcome ? 0 : 1)

            Spacer(minLength: 24)

            ZStack {
                page
                    .id(step)
                    .transition(
                        .asymmetric(
                            insertion: .offset(x: forward ? 48 : -48).combined(with: .opacity),
                            removal: .offset(x: forward ? -48 : 48).combined(with: .opacity)
                        )
                    )
            }
            .frame(maxWidth: 500)

            Spacer(minLength: 24)

            footer
                .frame(maxWidth: 500)
                .padding(.bottom, 34)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(duration: 0.45, bounce: 0.2), value: step)
        .onAppear {
            if userName.isEmpty { userName = Preferences.systemFirstName }
        }
    }

    // MARK: - Navegación

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases.dropFirst(), id: \.self) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(.primary.opacity(0.15)))
                    .frame(width: item == step ? 28 : 8, height: 8)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if step != .welcome {
                Button("Atrás") { go(to: step.rawValue - 1) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let skipTitle {
                Button(skipTitle) { advance() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Button(action: primaryAction) {
                Text(primaryTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 10)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!canContinue)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Empezar"
        case .microphone: state.microphoneGranted ? "Continuar" : "Permitir micrófono"
        case .accessibility: state.accessibilityGranted ? "Continuar" : "Abrir Ajustes"
        case .tryIt: "Empezar a usar stepbro whispr"
        default: "Continuar"
        }
    }

    private var skipTitle: String? {
        switch step {
        case .microphone where !state.microphoneGranted: "Ahora no"
        case .accessibility where !state.accessibilityGranted: "Ahora no"
        case .tryIt where !triedIt: "Saltar"
        default: nil
        }
    }

    private var canContinue: Bool {
        step != .name || !userName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func primaryAction() {
        switch step {
        case .microphone where !state.microphoneGranted:
            state.requestMicrophone()
        case .accessibility where !state.accessibilityGranted:
            state.requestAccessibility()
        default:
            advance()
        }
    }

    private func advance() {
        if step == .tryIt {
            onFinish()
        } else {
            go(to: step.rawValue + 1)
        }
    }

    private func go(to index: Int) {
        guard let next = OnboardingStep(rawValue: index) else { return }
        forward = index > step.rawValue
        if next == .name { userName = userName.trimmingCharacters(in: .whitespaces) }
        if next == .tryIt { lastDictationID = state.history.items.first?.id }
        step = next
    }

    // MARK: - Páginas

    @ViewBuilder
    private var page: some View {
        switch step {
        case .welcome: welcome
        case .name: name
        case .microphone: microphone
        case .accessibility: accessibility
        case .hotkey: hotkeyPage
        case .language: languagePage
        case .tryIt: tryItPage
        }
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            LogoMark()
                .filled()
                .frame(width: 120, height: 80)
                .scaleEffect(logoShown ? 1 : 0.8)
                .opacity(logoShown ? 1 : 0)
                .frame(height: 100)
                .onAppear {
                    withAnimation(.spring(duration: 0.7, bounce: 0.35).delay(0.1)) { logoShown = true }
                }
            VStack(spacing: 12) {
                Text("Te damos la bienvenida\na stepbro whispr")
                    .font(.display(40))
                    .multilineTextAlignment(.center)
                Text("Escribe con la voz en cualquier app: mantén una tecla, habla y suelta. Todo se procesa en tu Mac.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    FeatureChip(symbol: "lock.fill", text: "Privado")
                    FeatureChip(symbol: "bolt.fill", text: "Instantáneo")
                    FeatureChip(symbol: "app.badge.checkmark", text: "En cualquier app")
                }
            }
            .padding(.top, 6)
        }
    }

    private var name: some View {
        StepLayout(
            symbol: "person.crop.circle",
            tint: .blue,
            title: "¿Cómo te llamas?",
            message: "Así sabremos cómo saludarte."
        ) {
            TextField("Tu nombre", text: $userName)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .frame(width: 320, height: 56)
                .glassEffect(.regular, in: .capsule)
        }
    }

    private var microphone: some View {
        StepLayout(
            symbol: "microphone",
            tint: .red,
            title: "Permite el micrófono",
            message: "stepbro whispr solo escucha mientras mantienes la tecla. El audio se procesa en tu Mac y nunca sale de él."
        ) {
            VStack(spacing: 16) {
                StatusPill(done: state.microphoneGranted, doneText: "Micrófono permitido", pendingText: "Pendiente")
                if let current = AudioDevices.defaultInput(), current.isBluetooth,
                   let used = AudioDevices.preferredInput(uid: "") {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: current.name.localizedCaseInsensitiveContains("AirPods") ? "airpods" : "headphones")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                        Text("Usas «\(current.name)». Para que tu música no pierda calidad mientras dictas, stepbro whispr grabará con «\(used.name)». Puedes cambiarlo en Ajustes.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: 420)
                    .background(.primary.opacity(0.045), in: .rect(cornerRadius: 22))
                }
            }
        }
    }

    private var accessibility: some View {
        StepLayout(
            symbol: "accessibility",
            tint: .blue,
            title: "Activa Accesibilidad",
            message: "stepbro whispr la necesita para detectar la tecla y pegar el texto donde estés escribiendo."
        ) {
            VStack(spacing: 18) {
                if !state.accessibilityGranted {
                    SoftCard(padding: 18) {
                        VStack(alignment: .leading, spacing: 14) {
                            Instruction(number: 1, text: "Pulsa «Abrir Ajustes». Si macOS muestra un aviso, elige «Abrir Ajustes del Sistema».")
                            Instruction(number: 2, text: "Busca stepbro whispr en la lista y activa su interruptor:")
                            SettingsRowPreview()
                                .padding(.leading, 34)
                            Text("macOS puede pedirte tu contraseña o Touch ID.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 34)
                        }
                    }
                    .frame(maxWidth: 420)
                }
                StatusPill(done: state.accessibilityGranted, doneText: "Accesibilidad activada", pendingText: "Esperando el permiso…")
            }
        }
    }

    private var hotkeyPage: some View {
        StepLayout(
            symbol: "keyboard",
            tint: .indigo,
            title: "Elige tu tecla",
            message: "Mantenla pulsada mientras hablas y suéltala al terminar. Con doble toque dictas sin mantenerla."
        ) {
            VStack(spacing: 18) {
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        ForEach(Hotkey.allCases) { option in
                            HotkeyOption(hotkey: option, isSelected: hotkey == option, namespace: glassNamespace) {
                                withAnimation(.spring(duration: 0.4, bounce: 0.25)) { hotkey = option }
                            }
                        }
                    }
                }
                if hotkey == .fn {
                    globeHint
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.spring(duration: 0.35), value: hotkey)
        }
    }

    private var globeHint: some View {
        HStack(spacing: 12) {
            Image(systemName: state.globeKeyFree ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: 18))
                .foregroundStyle(state.globeKeyFree ? .green : .orange)
            Text(state.globeKeyFree
                 ? "La tecla del globo está libre."
                 : "macOS usa esta tecla para los emojis. En Teclado, cambia la acción de la tecla del globo a «No hacer nada».")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if !state.globeKeyFree {
                Button("Abrir Teclado") { Permissions.open(.keyboard) }
                    .buttonStyle(.glass)
            }
        }
        .padding(14)
        .frame(maxWidth: 440)
        .background(.primary.opacity(0.045), in: .rect(cornerRadius: 22))
    }

    private var languagePage: some View {
        StepLayout(
            symbol: "character.bubble",
            tint: .purple,
            title: "Idioma y estilo",
            message: "Elige en qué idioma vas a dictar. El modelo de voz se descarga una sola vez."
        ) {
            SoftCard {
                VStack(spacing: 0) {
                    HStack {
                        Text("Idioma")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        CapsuleMenu(selection: $language, options: languageOptions)
                        .onChange(of: language) { state.prepareModel() }
                    }
                    .padding(16)
                    CardDivider()
                    modelStatus
                        .padding(16)
                    CardDivider()
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Pulir con Apple Intelligence")
                                .font(.system(size: 14, weight: .medium))
                            Text(state.localPolisher.unavailableReason ?? "Quita muletillas y pone puntuación, mayúsculas y tildes.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Toggle("", isOn: $polish)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(!state.localPolisher.isAvailable)
                    }
                    .padding(16)
                }
            }
            .frame(maxWidth: 440)
        }
    }

    private var languageOptions: [(value: String, title: String)] {
        [("", "Del sistema")] + state.supportedLocales.map { ($0.identifier, $0.displayName) }
    }

    @ViewBuilder
    private var modelStatus: some View {
        HStack(spacing: 10) {
            switch state.modelStatus {
            case .ready(let locale):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Modelo de voz listo: \(locale.displayName)")
            case .checking:
                ProgressView().controlSize(.small)
                Text("Comprobando el modelo de voz…")
            case .downloading(let fraction):
                ProgressView(value: fraction).frame(width: 120)
                Text("Descargando… \(Int(fraction * 100)) %")
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text(message)
                Spacer()
                Button("Reintentar", action: state.prepareModel)
                    .buttonStyle(.glass)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
    }

    private var triedIt: Bool {
        guard let first = state.history.items.first else { return false }
        return first.id != lastDictationID
    }

    private var tryItPage: some View {
        StepLayout(
            symbol: "waveform",
            tint: .pink,
            title: triedIt ? "¡Funciona!" : "Pruébalo",
            message: triedIt
                ? "Ya puedes dictar en cualquier app. Mantén \(hotkey.shortName), habla y suelta."
                : "Haz clic en el recuadro, mantén \(hotkey.shortName) y di algo como «Hola, esto es una prueba»."
        ) {
            SoftCard(padding: 18) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $sample)
                        .font(.system(size: 16))
                        .scrollContentBackground(.hidden)
                        .frame(height: 110)
                    if sample.isEmpty {
                        Text("Haz clic aquí y mantén \(hotkey.shortName)…")
                            .font(.system(size: 16))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(maxWidth: 440)
            .overlay {
                if triedIt {
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(.green.opacity(0.6), lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
            }
            .animation(.default, value: triedIt)
        }
    }
}

// MARK: - Piezas

/// Estructura común de cada paso: símbolo grande, título, explicación y contenido.
private struct StepLayout<Content: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    @ViewBuilder var content: Content

    @State private var showSymbol = false

    var body: some View {
        VStack(spacing: 22) {
            // Como en las bienvenidas de Apple: el símbolo solo, con degradado,
            // que se dibuja con un trazo al aparecer.
            ZStack {
                if showSymbol {
                    Image(systemName: symbol)
                        .font(.system(size: 66, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [tint.mix(with: .white, by: 0.3), tint],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: tint.opacity(0.35), radius: 18, y: 6)
                        .transition(.symbolEffect(.drawOn.byLayer))
                }
            }
            .frame(height: 84)
            .task {
                try? await Task.sleep(for: .milliseconds(150))
                showSymbol = true
            }
            VStack(spacing: 10) {
                Text(title)
                    .font(.display(34))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 440)
            }
            content
                .padding(.top, 4)
        }
    }
}

private struct FeatureChip: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .frame(height: 32)
            .glassEffect(.regular, in: .capsule)
    }
}

private struct StatusPill: View {
    let done: Bool
    let doneText: String
    let pendingText: String

    var body: some View {
        HStack(spacing: 8) {
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            Text(done ? doneText : pendingText)
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .glassEffect(.regular.tint(done ? .green.opacity(0.25) : .clear), in: .capsule)
        .animation(.spring(duration: 0.35), value: done)
    }
}

private struct Instruction: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 22, height: 22)
                .background(.primary.opacity(0.08), in: .circle)
            Text(text)
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Dibujo de la fila de stepbro whispr en Ajustes del Sistema, con el interruptor
/// encendiéndose y apagándose para enseñar qué hay que tocar.
private struct SettingsRowPreview: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 22, height: 22)
            Text("stepbro whispr")
                .font(.system(size: 13))
            Spacer()
            PhaseAnimator([false, true]) { isOn in
                Capsule()
                    .fill(isOn ? Color.accentColor : Color.primary.opacity(0.18))
                    .frame(width: 34, height: 20)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                            .padding(2)
                    }
            } animation: { _ in
                .spring(duration: 0.35).delay(0.9)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.primary.opacity(0.06), in: .capsule)
        .overlay {
            Capsule()
                .strokeBorder(.primary.opacity(0.1))
                .allowsHitTesting(false)
        }
    }
}

/// Tarjeta para elegir la tecla; la seleccionada lleva una burbuja de cristal que se desplaza.
private struct HotkeyOption: View {
    let hotkey: Hotkey
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // El cristal va aplicado al propio contenido para que se dibuje detrás de él.
            if isSelected {
                label
                    .glassEffect(.regular.tint(Color.accentColor.opacity(0.22)).interactive(), in: .rect(cornerRadius: 28))
                    .glassEffectID("hotkey", in: namespace)
            } else {
                label
                    .background(.primary.opacity(0.04), in: .rect(cornerRadius: 28))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28)
                            .strokeBorder(.primary.opacity(0.08))
                            .allowsHitTesting(false)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private var label: some View {
        VStack(spacing: 12) {
            Text(hotkey.keySymbol)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .frame(width: 56, height: 46)
                .background(.primary.opacity(0.08), in: .capsule)
                .overlay {
                    Capsule()
                        .strokeBorder(.primary.opacity(0.15))
                        .allowsHitTesting(false)
                }
            Text(hotkey.longName)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
        }
        .frame(width: 140, height: 124)
        .contentShape(.rect)
    }
}
