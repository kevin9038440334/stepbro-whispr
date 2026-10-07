import AppKit
import Observation
import StepbroWhisprCore

/// Coordina atajo → grabación → transcripción → procesado del texto → pegado.
@MainActor
@Observable
final class AppState {
    enum Phase: Equatable {
        case idle
        case recording(handsFree: Bool)
        case transcribing
        case polishing
        case notice(String, isError: Bool)
    }

    enum ModelStatus: Equatable {
        case checking
        case downloading(Double)
        case ready(Locale)
        case failed(String)
    }

    static let levelCount = 24
    /// Pulsaciones más cortas que esto cuentan como toque, no como dictado.
    private static let tapThreshold: TimeInterval = 0.3
    private static let doubleTapWindow: TimeInterval = 0.5
    private static let escapeKeyCode: UInt16 = 53
    /// Un dictado se cierra solo pasado este tiempo, por si el modo manos libres se queda encendido.
    private static let recordingLimit: Duration = .seconds(600)

    private(set) var phase: Phase = .idle
    private(set) var levels = [Float](repeating: 0, count: levelCount)
    private(set) var modelStatus: ModelStatus = .checking
    private(set) var microphoneGranted = false
    private(set) var accessibilityGranted = false
    private(set) var globeKeyFree = false
    private(set) var supportedLocales: [Locale] = []
    /// La barra flotante lo actualiza cuando el ratón pasa por encima.
    var overlayHovered = false

    let history = HistoryStore()
    let groq = GroqService()
    let vocabulary: VocabularyStore
    let processor: TextProcessor

    @ObservationIgnored var onOverlayWillAppear: (() -> Void)?

    @ObservationIgnored private var engine = SpeechEngine()
    @ObservationIgnored private let hotkey = HotkeyMonitor()
    @ObservationIgnored private var engineQueue: Task<Void, Never>?
    @ObservationIgnored private var deliveryTask: Task<Void, Never>?
    @ObservationIgnored private var limitTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var modelTask: Task<Void, Never>?
    @ObservationIgnored private var permissionTask: Task<Void, Never>?
    @ObservationIgnored private var pressedAt: Date?
    @ObservationIgnored private var lastTapAt: Date?
    @ObservationIgnored private var ignoreNextRelease = false
    @ObservationIgnored private var recordingLocale = Locale.current
    @ObservationIgnored private var recordingStartedAt = Date.now
    @ObservationIgnored private var recordingTarget = DictationTarget(appName: nil, bundleID: nil)
    @ObservationIgnored private var didResetAccessibility = false
    /// En el modo automático, el segundo idioma que se escucha a la vez (inglés, o español si hablas inglés).
    @ObservationIgnored private var extraLocales: [Locale] = []
    /// Lo que hay escrito antes del cursor; se lee mientras hablas.
    @ObservationIgnored private var recordingContext = Task<DictationContext, Never> { .none }
    /// El dictado en curso, si es lo bastante largo para transcribirlo por partes.
    @ObservationIgnored private var live: LiveTranscript?
    /// Identifica el dictado en curso: lo que llegue tarde de uno anterior o cancelado se descarta.
    @ObservationIgnored private var recordingID: UUID?
    /// Peticiones a Groq del dictado que se está entregando, para cancelarlas con Esc.
    @ObservationIgnored private var currentJob: WhisperJob?

    init() {
        let vocabulary = VocabularyStore()
        self.vocabulary = vocabulary
        processor = TextProcessor(vocabulary: vocabulary, groq: groq)
    }

    var localPolisher: LocalPolisher { processor.local }

    var menuBarSymbol: String {
        switch phase {
        case .recording: "waveform.circle.fill"
        case .transcribing, .polishing: "ellipsis.circle"
        case .notice(_, true): "exclamationmark.circle"
        default: "waveform"
        }
    }

    var isReady: Bool {
        if case .ready = modelStatus { microphoneGranted && accessibilityGranted } else { false }
    }

    // MARK: - Arranque

    func launch() {
        Preferences.registerDefaults()
        hotkey.onPress = { [weak self] in self?.hotkeyPressed() }
        hotkey.onRelease = { [weak self] in self?.hotkeyReleased() }
        hotkey.onKeyDown = { [weak self] code in self?.keyPressed(code) }
        hotkey.start()

        refreshPermissions()
        watchPermissions()
        Task { supportedLocales = await SpeechEngine.supportedLocales() }
        prepareModel()
        groq.warmUp()
        runSelfTestIfRequested()
        runBenchIfRequested()
        UITest.runIfRequested()
    }

    func prepareModel() {
        modelTask?.cancel()
        modelTask = Task { [weak self] in
            guard let self else { return }
            modelStatus = .checking
            do {
                let automatic = Preferences.isAutomaticLanguage
                let locale = try await SpeechEngine.resolveLocale(automatic ? "" : Preferences.language)
                var extra: [Locale] = []
                if automatic {
                    let other = locale.language.languageCode?.identifier == "en" ? "es_ES" : "en_US"
                    if let second = try? await SpeechEngine.resolveLocale(other) { extra = [second] }
                }
                for model in [locale] + extra {
                    try await SpeechEngine.installModel(for: model) { [weak self] fraction in
                        self?.modelStatus = .downloading(fraction)
                    }
                }
                try Task.checkCancellation()
                extraLocales = extra
                modelStatus = .ready(locale)
            } catch is CancellationError {
            } catch {
                modelStatus = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Permisos

    func requestMicrophone() {
        if Permissions.microphone == .denied {
            Permissions.open(.microphone)
            return
        }
        Task {
            _ = await Permissions.requestMicrophone()
            refreshPermissions()
        }
    }

    func requestAccessibility() {
        // Una vez por sesión, limpia entradas viejas para que en la lista
        // solo aparezca la versión actual de la app y baste con activar su interruptor.
        if !didResetAccessibility, !Permissions.accessibilityGranted {
            Permissions.resetAccessibility()
            didResetAccessibility = true
        }
        Permissions.promptAccessibility()
        Permissions.open(.accessibility)
    }

    /// Solo asigna lo que cambia: cada asignación redibuja las vistas que lo leen,
    /// y esto se comprueba cada segundo.
    private func refreshPermissions() {
        let microphone = Permissions.microphone == .granted
        let accessibility = Permissions.accessibilityGranted
        let globe = Permissions.globeKeyIsFree
        if microphoneGranted != microphone { microphoneGranted = microphone }
        if accessibilityGranted != accessibility { accessibilityGranted = accessibility }
        if globeKeyFree != globe { globeKeyFree = globe }
    }

    /// Vigila Ajustes del Sistema para que la ventana refleje los permisos al momento.
    /// Cada segundo solo mientras falta alguno; con todo concedido basta de vez en cuando
    /// (y al volver a la app), para no despertar al Mac sin motivo.
    private func watchPermissions() {
        guard permissionTask == nil else { return }
        permissionTask = Task { [weak self] in
            while !Task.isCancelled {
                // La tecla Fn solo importa si es la elegida para dictar.
                let complete = self.map {
                    $0.microphoneGranted && $0.accessibilityGranted && (Preferences.hotkey != .fn || $0.globeKeyFree)
                } ?? true
                try? await Task.sleep(for: .seconds(complete ? 15 : 1))
                self?.checkPermissions()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPermissions() }
        }
    }

    private func checkPermissions() {
        let hadAccessibility = accessibilityGranted
        refreshPermissions()
        if accessibilityGranted, !hadAccessibility {
            // Los monitores globales no reciben eventos hasta reinstalarlos.
            hotkey.start()
        }
    }

    // MARK: - Atajo de teclado

    private func hotkeyPressed() {
        switch phase {
        case .recording(handsFree: true):
            ignoreNextRelease = true
            finishRecording()
        case .recording, .transcribing, .polishing:
            ignoreNextRelease = true
        case .idle, .notice:
            pressedAt = .now
            beginRecording(handsFree: false)
        }
    }

    private func hotkeyReleased() {
        if ignoreNextRelease {
            ignoreNextRelease = false
            return
        }
        guard phase == .recording(handsFree: false), let pressedAt else { return }
        self.pressedAt = nil

        let now = Date.now
        guard now.timeIntervalSince(pressedAt) < Self.tapThreshold else {
            finishRecording()
            return
        }
        // Doble toque: la grabación sigue sola hasta el siguiente toque.
        if let lastTapAt, now.timeIntervalSince(lastTapAt) < Self.doubleTapWindow {
            self.lastTapAt = nil
            phase = .recording(handsFree: true)
        } else {
            lastTapAt = now
            cancel()
        }
    }

    private func keyPressed(_ keyCode: UInt16) {
        switch phase {
        case .recording, .transcribing, .polishing:
            if keyCode == Self.escapeKeyCode {
                cancel()
            } else if hotkey.isHeld, phase == .recording(handsFree: false) {
                // Era una combinación (Fn+flecha, ⌥+letra…), no un dictado.
                ignoreNextRelease = true
                cancel()
            }
        default:
            break
        }
    }

    // MARK: - Barra flotante

    /// Clic en la barra flotante: empieza a dictar en manos libres o termina.
    func overlayTapped() {
        switch phase {
        case .recording:
            finishRecording()
        case .idle, .notice:
            beginRecording(handsFree: true)
        default:
            break
        }
    }

    // MARK: - Dictado

    private func beginRecording(handsFree: Bool) {
        guard case .ready(let locale) = modelStatus else {
            show(notice: modelStatusMessage, isError: true)
            return
        }
        guard microphoneGranted else {
            show(notice: "Falta el permiso de micrófono", isError: true)
            return
        }

        noticeTask?.cancel()
        recordingLocale = locale
        recordingStartedAt = .now
        recordingTarget = .frontmost()
        levels = [Float](repeating: 0, count: Self.levelCount)
        onOverlayWillAppear?()
        phase = .recording(handsFree: handsFree)
        if Preferences.sounds { Sounds.start.play() }
        processor.prepare()
        groq.warmUp()

        limitTask?.cancel()
        limitTask = Task { [weak self] in
            try? await Task.sleep(for: Self.recordingLimit)
            guard !Task.isCancelled, let self, case .recording = phase else { return }
            finishRecording()
        }

        let hints = vocabulary.hints
        let keepAudio = groq.transcribes
        let locales = [locale] + extraLocales
        let onLevel: @MainActor (Float) -> Void = { [weak self] level in
            self?.push(level: level)
        }
        let context = readContext(for: recordingTarget)
        recordingContext = context
        live?.cancel()
        live = nil
        // Los dictados largos se transcriben por partes mientras hablas. Con detección de idioma
        // van enteros: para respetar las mezclas hace falta comparar con lo que oyó Apple.
        let id = UUID()
        recordingID = id
        var onSegment: (@MainActor (URL?) -> Void)?
        if keepAudio, locales.count == 1 {
            let target = recordingTarget
            let language = locale.language.languageCode?.identifier
            onSegment = { [weak self] url in
                // Un corte puede terminar justo después de soltar la tecla: sigue siendo de este dictado.
                guard let self, recordingID == id else {
                    SpeechEngine.deleteAudio(url)
                    return
                }
                if live == nil {
                    let processor = processor
                    let job = Task { processor.makeJob(locale: locale, target: target, context: await context.value) }
                    live = LiveTranscript(groq: groq, processor: processor, job: job, language: language, hints: hints)
                }
                live?.add(url)
            }
        }
        enqueue { [weak self, engine] in
            do {
                try await engine.start(locales: locales, hints: hints, keepAudio: keepAudio, onLevel: onLevel, onSegment: onSegment)
            } catch {
                self?.recordingFailed(error, id: id)
            }
        }
    }

    private func finishRecording() {
        phase = .transcribing
        limitTask?.cancel()
        if Preferences.sounds { Sounds.stop.play() }

        let locale = recordingLocale
        let target = recordingTarget
        let duration = Date.now.timeIntervalSince(recordingStartedAt)
        let whisper = WhisperJob()
        currentJob = whisper
        let id = recordingID
        let groq = groq
        let context = recordingContext
        let hints = vocabulary.hints
        let languages = ([locale] + extraLocales).compactMap { $0.language.languageCode?.identifier }
        // En el modo automático, Whisper detecta el idioma él solo (y entiende mezclas).
        let whisperLanguage = languages.count > 1 ? nil : languages.first
        let result = enqueue { [engine] () async -> Result<SpeechEngine.Recording, Error> in
            // Margen para no cortar la última sílaba al soltar la tecla.
            try? await Task.sleep(for: .milliseconds(80))
            do {
                return .success(try await engine.stop { [weak self] audioURL, hasVoice in
                    guard let self, recordingID == id else {
                        SpeechEngine.deleteAudio(audioURL)
                        return
                    }
                    // Whisper arranca en paralelo con el final del reconocimiento de Apple.
                    if let live {
                        // Dictado largo: los trozos anteriores ya están hechos; solo falta este.
                        whisper.live = Task {
                            await live.finish(lastURL: audioURL, hasVoice: hasVoice) { self.showPolishing(id) }
                        }
                    } else if let audioURL, groq.canTranscribe {
                        whisper.task = Task { await groq.transcribe(audioURL: audioURL, language: whisperLanguage, hints: hints) }
                    }
                })
            } catch {
                return .failure(error)
            }
        }
        // Si el motor no devuelve el texto en 10 s, se reinicia en vez de quedarse cargando.
        let watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.engineStalled()
        }
        deliveryTask = Task { [weak self] in
            let outcome = await result.value
            watchdog.cancel()
            guard !Task.isCancelled else {
                // Cancelado con Esc mientras el motor paraba: el audio ya no hace falta.
                if case .success(let recording) = outcome { SpeechEngine.deleteAudio(recording.audioURL) }
                return
            }
            switch outcome {
            case .success(let recording):
                await self?.deliver(
                    recording, whisper: whisper, id: id, context: await context.value,
                    locale: locale, languages: languages, duration: duration, target: target
                )
            case .failure(SpeechEngine.Failure.notRunning):
                // El fallo al arrancar ya se mostró (o se muestra ahora); que no se quede «transcribiendo».
                if let self, phase == .transcribing || phase == .polishing { phase = .idle }
            case .failure(let error):
                self?.show(notice: error.localizedDescription, isError: true)
            }
        }
    }

    private func deliver(
        _ recording: SpeechEngine.Recording,
        whisper: WhisperJob,
        id: UUID?,
        context: DictationContext,
        locale: Locale,
        languages: [String],
        duration: TimeInterval,
        target: DictationTarget
    ) async {
        var raw = recording.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        var text: String?
        if TranscriptChooser.wasOnlyNoise(local: raw, seconds: duration) {
            whisper.live?.cancel()
            whisper.task?.cancel()
            self.live = nil
            SpeechEngine.deleteAudio(recording.audioURL)
            show(notice: "No te he oído", isError: false)
            return
        }
        if let live = whisper.live {
            // Dictado largo, ya transcrito y pulido por partes. Si algún trozo falló, se hace entero con Apple.
            // Traducido ya no se puede comparar con lo que oyó Apple.
            let translated = Preferences.translateTo.code != nil
            text = await live.value.map { translated ? $0 : TranscriptChooser.strippingTrailingHallucination($0, reference: raw) }
            self.live = nil
            // Si al texto por partes le falta mucho de lo que oyó Apple, se perdió algún trozo: mejor el de Apple entero.
            if let live = text, live.wordCount * 2 < raw.wordCount {
                SpeechEngine.log.error("al dictado por partes le falta texto (\(live.wordCount) palabras frente a \(raw.wordCount)); se usa lo de Apple")
                text = nil
            }
        } else {
            var alternative: String?
            if let whisper = whisper.task {
                // Whisper (Groq) suele ser más preciso; lo que oyó Apple va como segunda opinión.
                // Si la red va lenta, no se le espera más de la cuenta: el texto de Apple ya está listo.
                let whisperText = await Self.value(of: whisper, within: Self.whisperDeadline(forSeconds: duration))
                if whisperText == nil { groq.noteSlowNetwork() }
                let chosen = TranscriptChooser.choose(whisper: whisperText, local: raw)
                if chosen != raw, !raw.isEmpty { alternative = raw }
                raw = chosen
            }
            SpeechEngine.deleteAudio(recording.audioURL)
            guard !Task.isCancelled else { return }
            if !raw.isEmpty {
                text = await processor.process(
                    raw, alternative: alternative, locale: locale, languages: languages, target: target, context: context
                ) { [weak self] in
                    self?.showPolishing(id)
                }
            }
        }
        guard !Task.isCancelled else { return }
        if text == nil, whisper.live != nil, !raw.isEmpty {
            text = await processor.process(raw, locale: locale, languages: languages, target: target, context: context) { [weak self] in
                self?.showPolishing(id)
            }
            guard !Task.isCancelled else { return }
        }
        guard var text, !text.isEmpty else {
            show(notice: "No te he oído", isError: false)
            return
        }

        history.record(Dictation(text: text, date: .now, duration: duration, appName: target.appName, bundleID: target.bundleID))

        // Si lo de antes del cursor se quedó a media frase, el dictado la continúa.
        text = ContextJoiner.adapt(text, after: context.textBefore, keepingCase: vocabulary.entries.map(\.term))
        if Preferences.trailingSpace, !text.hasSuffix("\n") { text += " " }
        switch await TextInserter.insert(text) {
        case .pasted:
            phase = .idle
        case .copiedOnly:
            show(notice: "Copiado: falta permiso de Accesibilidad para pegar", isError: true)
        case .secureField:
            show(notice: "Es un campo de contraseña: no pego nada", isError: true)
        }
    }

    /// Pasa a «puliendo» solo si ese dictado sigue en curso (no si se canceló con Esc).
    private func showPolishing(_ id: UUID?) {
        guard recordingID == id, phase == .transcribing else { return }
        phase = .polishing
    }

    /// Lee, sin bloquear, lo que hay antes del cursor y recuerda el dictado anterior en la misma app.
    private func readContext(for target: DictationTarget) -> Task<DictationContext, Never> {
        guard Preferences.useContext, Preferences.polish else { return Task { .none } }
        var previous: String?
        if let last = history.items.first, last.appName == target.appName, Date.now.timeIntervalSince(last.date) < 180 {
            previous = last.text
        }
        let bundleID = target.bundleID
        return Task.detached(priority: .userInitiated) {
            DictationContext(textBefore: FocusContext.textBeforeCursor(bundleID: bundleID), previousDictation: previous)
        }
    }

    func cancel() {
        recordingID = nil
        deliveryTask?.cancel()
        deliveryTask = nil
        currentJob?.task?.cancel()
        currentJob?.live?.cancel()
        currentJob = nil
        live?.cancel()
        live = nil
        limitTask?.cancel()
        enqueue { [engine] in await engine.cancel() }
        phase = .idle
    }

    private func engineStalled() {
        SpeechEngine.log.error("la transcripción no termina: reinicio el motor")
        deliveryTask?.cancel()
        deliveryTask = nil
        engine.forceStop()
        recordingID = nil
        currentJob?.task?.cancel()
        currentJob?.live?.cancel()
        currentJob = nil
        live?.cancel()
        live = nil
        engine = SpeechEngine()
        engineQueue = nil
        show(notice: "No he podido transcribir. Inténtalo de nuevo.", isError: true)
    }

    private func recordingFailed(_ error: Error, id: UUID) {
        // También si ya se soltó la tecla: si no, se quedaría «transcribiendo» para siempre.
        guard recordingID == id, phase != .idle else { return }
        recordingID = nil
        deliveryTask?.cancel()
        deliveryTask = nil
        live?.cancel()
        live = nil
        limitTask?.cancel()
        enqueue { [engine] in await engine.cancel() }
        show(notice: error.localizedDescription, isError: true)
    }

    // MARK: - Utilidades

    /// Tiempo máximo de espera a Whisper: 2 s más 0,1 s por segundo de audio, hasta 4 s.
    /// Da para un segundo intento si el primero se atasca; pasado eso, se usa lo que oyó Apple.
    static func whisperDeadline(forSeconds seconds: TimeInterval) -> Duration {
        .milliseconds(Int(min(4, 2 + 0.1 * seconds) * 1000))
    }

    /// El resultado de la tarea, o nil si no llega a tiempo (y entonces la tarea se cancela:
    /// si no, el grupo se quedaría esperándola y el plazo no serviría de nada).
    static func value(of task: Task<String?, Never>, within deadline: Duration) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
            }
            group.addTask {
                try? await Task.sleep(for: deadline)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Ejecuta las operaciones del motor de una en una y en orden,
    /// aunque pulses y sueltes la tecla muy rápido.
    @discardableResult
    private func enqueue<T: Sendable>(_ operation: @escaping @MainActor () async -> T) -> Task<T, Never> {
        let previous = engineQueue
        let task = Task {
            await previous?.value
            return await operation()
        }
        engineQueue = Task { _ = await task.value }
        return task
    }

    private func push(level: Float) {
        guard case .recording = phase else { return }
        levels.removeFirst()
        levels.append(level)
    }

    private func show(notice: String, isError: Bool) {
        onOverlayWillAppear?()
        phase = .notice(notice, isError: isError)
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(isError ? 3 : 1.6))
            guard !Task.isCancelled, let self, case .notice = phase else { return }
            phase = .idle
        }
    }

    private var modelStatusMessage: String {
        switch modelStatus {
        case .checking: "Preparando el modelo de voz…"
        case .downloading(let fraction): "Descargando el modelo de voz (\(Int(fraction * 100)) %)"
        case .failed(let message): message
        case .ready: ""
        }
    }
}

/// La transcripción de Whisper en curso, que arranca antes de que Apple termine.
@MainActor
final class WhisperJob {
    var task: Task<String?, Never>?
    /// En un dictado largo: el texto final, ya pulido por partes (nil si hay que recurrir a Apple).
    var live: Task<String?, Never>?
}

@MainActor
enum Sounds {
    static let start = make("Tink")
    static let stop = make("Pop")

    private static func make(_ name: String) -> NSSound {
        let sound = NSSound(named: name) ?? NSSound()
        sound.volume = 0.25
        return sound
    }
}

// MARK: - Autoprueba

extension AppState {
    /// Diagnóstico: `SUSURRO_SELFTEST=/ruta/informe.txt` graba 3 s, transcribe y procesa
    /// el texto sin pegar nada, y escribe un informe con los tiempos de cada paso.
    func runSelfTestIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["SUSURRO_SELFTEST"] else { return }
        let report = SelfTestReport(path: path)

        // Variante para comprobar la lectura del texto antes del cursor, con un campo propio.
        if let sample = environment["SUSURRO_SELFTEST_CONTEXT"] {
            let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 420, height: 60), styleMask: [.titled], backing: .buffered, defer: false)
            let field = NSTextField(string: sample)
            field.frame = NSRect(x: 10, y: 16, width: 400, height: 28)
            window.contentView?.addSubview(field)
            Task {
                try? await Task.sleep(for: .seconds(2))
                NSApp.activate()
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(field)
                field.currentEditor()?.selectedRange = NSRange(location: (sample as NSString).length, length: 0)
                try? await Task.sleep(for: .seconds(1))
                let bundleID = Bundle.main.bundleIdentifier
                let began = ContinuousClock.now
                let before = await Task.detached { FocusContext.textBeforeCursor(bundleID: bundleID) }.value
                report.add("antes del cursor (\(ContinuousClock.now - began)): «\(before ?? "nil")»")
                report.add("continuación: «\(ContextJoiner.adapt("Lo revises cuando puedas.", after: before))»")
                report.add("terminado")
                window.close()
            }
            return
        }

        // Variante sin micrófono: procesa textos de prueba (separados por «|»)
        // como si se fueran a pegar en la app indicada.
        if let samples = environment["SUSURRO_SELFTEST_TEXT"] {
            let target = DictationTarget(appName: environment["SUSURRO_SELFTEST_APPNAME"], bundleID: environment["SUSURRO_SELFTEST_APP"])
            Task {
                for _ in 0..<60 {
                    if case .ready = modelStatus { break }
                    try? await Task.sleep(for: .milliseconds(500))
                }
                guard case .ready(let locale) = modelStatus else { return }
                report.add("estilo: \(vocabulary.style(for: target.category).title) (\(target.category.title)), pulido local \(localPolisher.isAvailable), Groq \(groq.polishes)")
                let clock = ContinuousClock()
                for sample in samples.split(separator: "|").map(String.init) {
                    let began = clock.now
                    let text = await processor.process(sample, locale: locale, target: target) {}
                    report.add("▶ \(sample)\n✔ \(text)\n  (\(clock.now - began))")
                    if let rejection = localPolisher.lastRejection {
                        report.add("  descartado → \(rejection)")
                    }
                }
                report.add("terminado")
            }
            return
        }

        Task {
            try? await Task.sleep(for: .seconds(120))
            if report.step != "terminado" { report.add("tiempo agotado: se quedó en «\(report.step)»") }
        }
        Task {
            for _ in 0..<60 {
                if case .ready = modelStatus { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
            report.add("modelo: \(modelStatus)")
            report.add("micrófono permitido: \(microphoneGranted)")
            report.add("micrófono elegido: \(AudioDevices.preferredInput(uid: Preferences.microphone)?.name ?? "el del sistema")")
            report.add("pulido: local \(localPolisher.isAvailable), Groq \(groq.polishes); Whisper \(groq.transcribes)")
            guard case .ready(let locale) = modelStatus else { return }

            let clock = ContinuousClock()
            do {
                report.step = "start"
                var began = clock.now
                let audioCopy = environment["SUSURRO_SELFTEST_AUDIO"]
                // SUSURRO_SELFTEST_SECONDS alarga la grabación para probar los cortes de un dictado largo.
                let seconds = environment["SUSURRO_SELFTEST_SECONDS"].flatMap(Double.init) ?? 3
                let processor = processor
                let job = Task { processor.makeJob(locale: locale, target: .init(appName: nil, bundleID: nil)) }
                let live = LiveTranscript(groq: groq, processor: processor, job: job, language: locale.language.languageCode?.identifier, hints: vocabulary.hints)
                try await engine.start(
                    locale: locale, hints: vocabulary.hints, keepAudio: groq.transcribes || audioCopy != nil,
                    onLevel: { _ in },
                    onSegment: { url in
                        let size = url.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int } ?? 0
                        report.add("trozo \(live.segments + 1) a los \(clock.now - began): \(size) bytes")
                        live.add(url)
                    }
                )
                report.add("start: \(clock.now - began)")
                report.step = "grabando"
                try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
                report.step = "stop"
                began = clock.now
                let recording = try await engine.stop()
                var raw = recording.transcript
                report.add("stop: \(clock.now - began), \(raw.count) caracteres (Apple)")
                report.add("Apple: \(raw)")
                if live.segments > 0 {
                    let text = await live.finish(lastURL: recording.audioURL, hasVoice: true) {}
                    report.add("por partes (\(live.segments + 1) trozos), listo a los \(clock.now - began) de soltar:\n\(text ?? "— falló —")")
                    report.step = "terminado"
                    report.add("terminado")
                    return
                }
                if let audioURL = recording.audioURL {
                    let size = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int) ?? 0
                    report.add("audio guardado: \(size) bytes")
                    if let audioCopy {
                        try? FileManager.default.copyItem(at: audioURL, to: URL(fileURLWithPath: audioCopy))
                    }
                    began = clock.now
                    let whisper = await groq.transcribe(audioURL: audioURL, language: locale.language.languageCode?.identifier, hints: vocabulary.hints)
                    report.add("whisper: \(clock.now - began), \(whisper?.count ?? -1) caracteres")
                    raw = TranscriptChooser.choose(whisper: whisper, local: raw)
                    SpeechEngine.deleteAudio(audioURL)
                }
                report.step = "procesando"
                began = clock.now
                let text = await processor.process(raw, locale: locale, target: .init(appName: nil, bundleID: nil)) {}
                report.add("procesado: \(clock.now - began), \(text.count) caracteres\n\(text)")
                report.step = "terminado"
                report.add("terminado")
            } catch {
                report.add("error: \(error)")
            }
        }
    }
}

@MainActor
private final class SelfTestReport {
    let path: String
    var step = "esperando el modelo"
    private var lines: [String] = []

    init(path: String) {
        self.path = path
    }

    func add(_ line: String) {
        lines.append(line)
        try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }
}
