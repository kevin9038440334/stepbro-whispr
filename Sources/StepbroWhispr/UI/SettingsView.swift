import StepbroWhisprCore
import SwiftUI
import Translation

struct SettingsView: View {
    let state: AppState

    @AppStorage(Preferences.hotkeyKey) private var hotkey: Hotkey = .fn
    @AppStorage(Preferences.languageKey) private var language = ""
    @AppStorage(Preferences.polishKey) private var polish = true
    @AppStorage(Preferences.trailingSpaceKey) private var trailingSpace = true
    @AppStorage(Preferences.soundsKey) private var sounds = true
    @AppStorage(Preferences.showInMenuBarKey) private var showInMenuBar = true
    @AppStorage(Preferences.alwaysShowBarKey) private var alwaysShowBar = true
    @AppStorage(Preferences.userNameKey) private var userName = ""
    @AppStorage(Preferences.onboardingDoneKey) private var onboardingDone = true
    @AppStorage(Preferences.microphoneKey) private var microphone = ""
    @State private var microphones: [AudioInputDevice] = []
    @AppStorage(Preferences.engineKey) private var engine: DictationEngine = .apple
    @AppStorage(Preferences.translateKey) private var translateTo: TranslationTarget = .none
    @State private var translationStatus: LanguageAvailability.Status?
    @State private var downloadConfiguration: TranslationSession.Configuration?
    @AppStorage(Preferences.groqWhisperModelKey) private var whisperModel: WhisperModel = .turbo
    @AppStorage(Preferences.groqChatModelKey) private var groqModel: GroqChatModel = .qwen
    @AppStorage(Preferences.useContextKey) private var useContext = true
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?
    @State private var confirmClear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("Ajustes")
                    .font(.display(34))

                group("Motor de dictado") {
                    EnginePicker(selection: $engine)
                        .padding(16)
                    CardDivider()
                    if engine == .groq {
                        GroqKeyRow(groq: state.groq)
                        CardDivider()
                        SettingRow("Modelo de voz", detail: whisperModel.summary) {
                            CapsuleMenu(selection: $whisperModel, options: WhisperModel.allCases.map { ($0, $0.title) })
                        }
                        CardDivider()
                        SettingRow("Modelo de texto", detail: groqModel.summary + " Si llega a su límite o va lento, responde otro.") {
                            CapsuleMenu(selection: $groqModel, options: GroqChatModel.allCases.map { ($0, $0.title) })
                        }
                    } else {
                        SettingRow(
                            "Apple Intelligence",
                            detail: state.localPolisher.unavailableReason ?? "Pule el texto en tu Mac, sin enviar nada a ningún sitio."
                        ) {
                            Image(systemName: state.localPolisher.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(state.localPolisher.isAvailable ? .green : .orange)
                        }
                    }
                }

                group("Idioma") {
                    SettingRow("Idioma que hablas", detail: languageDetail) {
                        CapsuleMenu(
                            selection: $language,
                            options: [(Preferences.automaticLanguage, "Automático (español e inglés)"), ("", "Del sistema")]
                                + state.supportedLocales.map { ($0.identifier, $0.displayName) }
                        )
                        .onChange(of: language) { state.prepareModel() }
                    }
                    CardDivider()
                    SettingRow("Traducir a", detail: translationDetail) {
                        CapsuleMenu(selection: $translateTo, options: TranslationTarget.allCases.map { ($0, $0.title) })
                    }
                    if engine == .apple, translateTo != .none, translationStatus == .supported {
                        CardDivider()
                        SettingRow("Idioma de traducción", detail: "Hay que descargarlo una vez para traducir en tu Mac, sin internet.") {
                            Button("Descargar") {
                                downloadConfiguration = .init(
                                    source: Locale.Language(identifier: spokenLanguage),
                                    target: Locale.Language(identifier: translateTo.rawValue)
                                )
                                // Vigila hasta que el idioma quede descargado.
                                Task {
                                    for _ in 0..<90 {
                                        try? await Task.sleep(for: .seconds(2))
                                        await refreshTranslationStatus()
                                        if translationStatus == .installed { break }
                                    }
                                }
                            }
                            .buttonStyle(.glassProminent)
                        }
                    }
                }
                .task(id: "\(translateTo.rawValue)-\(engine.rawValue)-\(language)") { await refreshTranslationStatus() }
                .translationTask(downloadConfiguration, action: Self.downloadLanguages)

                group("Tú") {
                    SettingRow("Nombre", detail: "Para saludarte en Inicio.") {
                        TextField("Tu nombre", text: $userName)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .frame(width: 180, height: 30)
                            .glassEffect(.regular, in: .capsule)
                    }
                    CardDivider()
                    SettingRow("Bienvenida", detail: "Repasa los permisos y la configuración paso a paso.") {
                        Button("Ver de nuevo") {
                            withAnimation(.easeInOut(duration: 0.4)) { onboardingDone = false }
                        }
                        .buttonStyle(.glass)
                    }
                }

                group("Dictado") {
                    SettingRow("Tecla para dictar", detail: "Mantenla pulsada mientras hablas. Doble toque para manos libres.") {
                        CapsuleMenu(selection: $hotkey, options: Hotkey.allCases.map { ($0, $0.title) })
                    }
                    CardDivider()
                    SettingRow("Micrófono", detail: microphoneDetail) {
                        CapsuleMenu(
                            selection: $microphone,
                            options: [("", "Automático")] + microphones.map { ($0.uid, $0.name) }
                        )
                    }
                    CardDivider()
                    SettingRow("Sonidos", detail: "Un toque suave al empezar y al terminar.") {
                        Toggle("", isOn: $sounds)
                    }
                }

                group("Texto") {
                    SettingRow(
                        "Pulir el texto",
                        detail: "Quita muletillas («eh», «este»), aplica autocorrecciones y pone puntuación, mayúsculas y tildes. "
                            + (engine == .groq ? "Lo hace \(groqModel.title) en Groq." : "Lo hace Apple Intelligence en tu Mac.")
                    ) {
                        Toggle("", isOn: $polish)
                            .disabled(!state.processor.canPolish)
                    }
                    CardDivider()
                    SettingRow(
                        "Tener en cuenta lo ya escrito",
                        detail: "Lee lo que hay antes del cursor para continuar la frase y escribir igual los nombres. "
                            + (engine == .groq ? "Ese fragmento se envía a Groq junto al dictado." : "No sale de tu Mac.")
                    ) {
                        Toggle("", isOn: $useContext)
                            .disabled(!polish)
                    }
                    CardDivider()
                    SettingRow("Espacio al final", detail: "Para encadenar dictados sin juntar las frases.") {
                        Toggle("", isOn: $trailingSpace)
                    }
                }

                group("Apariencia") {
                    SettingRow("Barra flotante siempre visible", detail: "Una pastilla pequeña abajo; haz clic en ella para dictar.") {
                        Toggle("", isOn: $alwaysShowBar)
                    }
                    CardDivider()
                    SettingRow("Icono en la barra de menús") {
                        Toggle("", isOn: $showInMenuBar)
                    }
                    CardDivider()
                    SettingRow("Abrir al iniciar sesión", detail: launchAtLoginError) {
                        Toggle("", isOn: $launchAtLogin)
                            .onChange(of: launchAtLogin) { _, enabled in
                                do {
                                    try LaunchAtLogin.set(enabled)
                                    launchAtLoginError = nil
                                } catch {
                                    launchAtLoginError = error.localizedDescription
                                }
                            }
                    }
                }

                group("Permisos") {
                    SettingRow("Micrófono") {
                        PermissionState(granted: state.microphoneGranted, request: state.requestMicrophone)
                    }
                    CardDivider()
                    SettingRow("Accesibilidad") {
                        PermissionState(granted: state.accessibilityGranted, request: state.requestAccessibility)
                    }
                }

                group("Datos") {
                    SettingRow("Historial", detail: "\(state.history.items.count) dictados guardados en este Mac.") {
                        Button("Borrar…", role: .destructive) { confirmClear = true }
                            .buttonStyle(.glass)
                            .disabled(state.history.items.isEmpty)
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 18)
            .padding(.bottom, 36)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .onAppear { microphones = AudioDevices.inputs() }
        .toggleStyle(.switch)
        .confirmationDialog("¿Borrar todo el historial?", isPresented: $confirmClear) {
            Button("Borrar todo", role: .destructive, action: state.history.clear)
        } message: {
            Text("No se puede deshacer.")
        }
    }

    /// Muestra el aviso del sistema para descargar los idiomas de traducción.
    nonisolated private static func downloadLanguages(_ session: TranslationSession) async {
        try? await session.prepareTranslation()
    }

    /// Idioma principal en que se habla (para saber desde qué idioma traducir).
    private var spokenLanguage: String {
        if !language.isEmpty, language != Preferences.automaticLanguage {
            return Locale(identifier: language).language.languageCode?.identifier ?? "es"
        }
        return Locale.current.language.languageCode?.identifier ?? "es"
    }

    private var languageDetail: String {
        guard language == Preferences.automaticLanguage else {
            return "El modelo de voz se descarga la primera vez."
        }
        return engine == .groq
            ? "Whisper detecta el idioma de cada frase: puedes mezclar español e inglés y cada parte se queda en su idioma."
            : "Apple escucha en español y en inglés a la vez y se queda con el más seguro. Para mezclar idiomas en la misma frase, usa Groq."
    }

    private var translationDetail: String {
        guard translateTo != .none else { return "El texto se queda en el idioma en que hablas." }
        if engine == .groq {
            return "Lo traduce \(groqModel.title) en el mismo paso que el pulido, sin esperas extra."
        }
        switch translationStatus {
        case .installed: return "Lo traduce la traducción de Apple, en tu Mac y sin internet."
        case .supported: return "Lo traduce la traducción de Apple; falta descargar el idioma."
        case .unsupported: return "La traducción de Apple no admite este par de idiomas."
        default: return "Comprobando la traducción de Apple…"
        }
    }

    private func refreshTranslationStatus() async {
        guard let target = translateTo.code else {
            translationStatus = nil
            return
        }
        translationStatus = await state.processor.translator.status(from: spokenLanguage, to: target)
    }

    private var microphoneDetail: String {
        guard microphone.isEmpty else { return "stepbro whispr siempre graba con este micrófono." }
        if let current = AudioDevices.defaultInput(), current.isBluetooth,
           let used = AudioDevices.preferredInput(uid: "") {
            return "Usas \(current.name): stepbro whispr graba con «\(used.name)» para que tu música no pierda calidad."
        }
        return "El del sistema. Con auriculares Bluetooth usa el del Mac, para que tu música no pierda calidad."
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: title)
            SoftCard {
                VStack(spacing: 0, content: content)
            }
        }
    }
}

private struct SettingRow<Control: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder var control: Control

    init(_ title: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                if let detail {
                    Text(detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            control
                .labelsHidden()
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

private struct PermissionState: View {
    let granted: Bool
    let request: () -> Void

    var body: some View {
        if granted {
            Label("Concedido", systemImage: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.green)
        } else {
            Button("Conceder", action: request)
                .buttonStyle(.glassProminent)
        }
    }
}

/// Clave de la API de Groq: se guarda en un archivo privado y se puede comprobar.
private struct GroqKeyRow: View {
    let groq: GroqService

    @State private var draft = ""
    @State private var checking = false
    @State private var result: String?
    @State private var succeeded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Clave de API")
                        .font(.system(size: 14, weight: .medium))
                    Text(groq.hasKey ? "Guardada en tu Mac; solo tu usuario puede leerla." : "Empieza por «gsk_». Se guarda en tu Mac y solo tu usuario puede leerla.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 16)
                if groq.hasKey {
                    Button("Comprobar") { Task { await check(nil) } }
                        .buttonStyle(.glass)
                        .disabled(checking)
                    Button("Borrar", role: .destructive) {
                        groq.removeKey()
                        result = nil
                    }
                    .buttonStyle(.glass)
                } else {
                    SecureField("gsk_…", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 14)
                        .frame(width: 220, height: 30)
                        .glassEffect(.regular, in: .capsule)
                        .onSubmit { Task { await check(draft) } }
                    Button("Guardar") { Task { await check(draft) } }
                        .buttonStyle(.glassProminent)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || checking)
                }
            }
            HStack(spacing: 8) {
                if checking {
                    ProgressView().controlSize(.small)
                    Text("Comprobando con Groq…")
                } else if let result {
                    Image(systemName: succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(succeeded ? .green : .orange)
                    Text(result)
                } else if let error = groq.lastError {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Último fallo: \(error)")
                } else if !groq.hasKey {
                    Link("Conseguir una clave gratis en console.groq.com", destination: URL(string: "https://console.groq.com/keys")!)
                }
            }
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    /// Guarda la clave nueva (si la hay) después de comprobar que funciona.
    private func check(_ newKey: String?) async {
        checking = true
        defer { checking = false }
        if let newKey {
            let key = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            if let error = await groq.test(key: key) {
                succeeded = false
                result = error
                return
            }
            groq.setKey(key)
            draft = ""
        } else if let error = await groq.testSavedKey() {
            succeeded = false
            result = error
            return
        }
        succeeded = true
        result = "La clave funciona."
    }
}

/// Dos tarjetas para elegir el motor; la elegida lleva una burbuja de cristal que se desplaza.
private struct EnginePicker: View {
    @Binding var selection: DictationEngine
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(DictationEngine.allCases) { engine in
                    EngineCard(engine: engine, isSelected: engine == selection, namespace: glass) {
                        withAnimation(.spring(duration: 0.4, bounce: 0.25)) { selection = engine }
                    }
                }
            }
        }
    }
}

private struct EngineCard: View {
    let engine: DictationEngine
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isSelected {
                label
                    .glassEffect(.regular.tint(Color.accentColor.opacity(0.22)).interactive(), in: .rect(cornerRadius: 24))
                    .glassEffectID("engine", in: namespace)
            } else {
                label
                    .background(.primary.opacity(0.04), in: .rect(cornerRadius: 24))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(.primary.opacity(0.08))
                            .allowsHitTesting(false)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: engine.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(engine.title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(engine.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            Text(engine.summary)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}
