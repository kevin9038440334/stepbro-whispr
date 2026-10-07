import AVFoundation
import os
import Speech
import StepbroWhisprCore

/// Graba el micrófono y lo transcribe en local con SpeechAnalyzer.
@MainActor
final class SpeechEngine {
    enum Failure: LocalizedError {
        case unsupportedDevice
        case unsupportedLocale(Locale)
        case microphoneUnavailable
        case notRunning

        var errorDescription: String? {
            switch self {
            case .unsupportedDevice:
                "Este Mac no admite el reconocimiento de voz local de Apple."
            case .unsupportedLocale(let locale):
                "El idioma \(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier) no está disponible para dictado."
            case .microphoneUnavailable:
                "No encuentro ningún micrófono."
            case .notRunning:
                "No había ninguna grabación en curso."
            }
        }
    }

    /// Resultado de una grabación: lo que entendió Apple y, si se pidió, el audio en un archivo temporal.
    struct Recording: Sendable {
        let transcript: String
        let audioURL: URL?
        /// Idioma en que Apple lo entendió mejor (en el modo automático, el más seguro de los dos).
        let locale: Locale?
    }

    /// Una transcripción con la seguridad media con que Apple la reconoció (0–1).
    private struct Scored: Sendable {
        var text = ""
        var confidence = 0.0
        var characters = 0

        var averageConfidence: Double { characters == 0 ? 0 : confidence / Double(characters) }

        mutating func add(_ segment: AttributedString) {
            text.appendSegment(String(segment.characters))
            for run in segment.runs {
                guard let value = run[AttributeScopes.SpeechAttributes.ConfidenceAttribute.self] else { continue }
                let length = segment[run.range].characters.count
                confidence += value * Double(length)
                characters += length
            }
        }
    }

    /// Un reconocedor por idioma: uno normalmente, dos en el modo automático.
    private struct Lane {
        let locale: Locale
        let analyzer: SpeechAnalyzer
        let input: AsyncStream<AnalyzerInput>.Continuation
        let transcript: Task<Scored, Error>
    }

    private struct Session {
        let capture: AVCaptureSession
        let lanes: [Lane]
        let pump: Task<Void, Never>
        let meter: Task<Void, Never>
        let counters: AudioCounters
        let recorder: AudioFileRecorder?
    }

    /// Registro de diagnóstico: `log show --predicate 'subsystem == "com.susurro.Susurro"'`.
    nonisolated static let log = Logger(subsystem: "com.susurro.Susurro", category: "motor")

    private var session: Session?
    /// Corte en curso de un dictado largo: `stop` lo espera para entregar los trozos en orden.
    private var rotation: Task<Void, Never>?
    /// Segundos con voz desde el último corte: si no hay, el último trozo es silencio.
    private var voicedSinceCut: TimeInterval = 0

    // MARK: - Modelo

    static func resolveLocale(_ identifier: String) async throws -> Locale {
        guard SpeechTranscriber.isAvailable else { throw Failure.unsupportedDevice }
        let wanted = identifier.isEmpty ? Locale.current : Locale(identifier: identifier)
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: wanted) else {
            throw Failure.unsupportedLocale(wanted)
        }
        return locale
    }

    static func supportedLocales() async -> [Locale] {
        await SpeechTranscriber.supportedLocales.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    /// Descarga el modelo del idioma si aún no está en el Mac.
    static func installModel(for locale: Locale, onProgress: @escaping @MainActor (Double) -> Void) async throws {
        _ = try? await AssetInventory.reserve(locale: locale)
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else { return }

        let progress = request.progress
        let poller = Task {
            while !Task.isCancelled {
                onProgress(progress.fractionCompleted)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer { poller.cancel() }
        try await request.downloadAndInstall()
    }

    /// Transcribe un archivo de audio con el reconocimiento de Apple (para el banco de pruebas).
    static func transcribeFile(_ url: URL, locale: Locale, hints: [String]) async throws -> String {
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if !hints.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = hints
            try? await analyzer.setContext(context)
        }
        let collect = Task {
            var text = ""
            for try await result in transcriber.results {
                text.appendSegment(String(result.text.characters))
            }
            return text
        }
        try await analyzer.start(inputAudioFile: try AVAudioFile(forReading: url), finishAfterFile: true)
        return try await collect.value
    }

    // MARK: - Grabación

    /// Graba con una sesión de captura propia: así el micrófono es independiente
    /// de los altavoces y se puede usar el del Mac aunque suenen los AirPods.
    /// `locales`: uno, o varios para detectar el idioma (se escucha en todos y gana el más seguro).
    /// `hints`: palabras del diccionario que el reconocimiento debe esperar.
    /// `keepAudio`: guarda también el audio en un archivo temporal (para Whisper).
    /// `onSegment`: si se da, un dictado largo se corta en las pausas y cada trozo de audio
    /// se entrega en cuanto se cierra, mientras la grabación sigue.
    func start(
        locales: [Locale],
        hints: [String] = [],
        keepAudio: Bool = false,
        onLevel: @escaping @MainActor (Float) -> Void,
        onSegment: (@MainActor (URL?) -> Void)? = nil
    ) async throws {
        await cancel()
        voicedSinceCut = 0
        let clock = ContinuousClock()
        let began = clock.now

        let uid = AudioDevices.preferredInput(uid: Preferences.microphone)?.uid
        let (provider, transcribers, recorder) = try await Self.makeCapture(
            microphoneUID: uid,
            locales: locales,
            keepAudio: keepAudio
        ).value
        let capture = provider.captureSession
        Self.log.notice("micrófono en marcha (\(clock.now - began, privacy: .public))")

        // Un stream propio por reconocedor, para repartir el mismo audio y cerrarlos al terminar.
        let pairs = transcribers.map { _ in AsyncStream.makeStream(of: AnalyzerInput.self) }
        let feeds = pairs.map(\.continuation)
        let counters = AudioCounters()
        let inputs = provider.analyzerInputs
        let pump = Task.detached {
            do {
                for try await input in inputs {
                    for feed in feeds { feed.yield(input) }
                    counters.count()
                }
            } catch {
                Self.log.error("audio interrumpido: \(error.localizedDescription, privacy: .public)")
            }
        }

        let channel = provider.captureAudioDataOutput.connections.first?.audioChannels.first
        var detector = PauseDetector()
        // Para las pruebas: SUSURRO_SEGMENT_SECONDS adelanta los cortes.
        if let seconds = ProcessInfo.processInfo.environment["SUSURRO_SEGMENT_SECONDS"].flatMap(Double.init) {
            detector.minimum = seconds
            detector.relaxedAfter = seconds * 1.5
            detector.maximum = seconds * 2
        }
        let meter = Task { [weak self] in
            var last = clock.now
            while !Task.isCancelled {
                let level = Self.normalized(decibels: channel?.averagePowerLevel ?? -160)
                onLevel(level)
                let now = clock.now
                let elapsed = now - last
                last = now
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                let cut = detector.feed(level: level, elapsed: seconds)
                self?.voicedSinceCut = detector.voiced
                if cut, let onSegment, let recorder {
                    self?.rotation = Task {
                        // nil: el trozo se ha perdido, y quien lo recibe debe saberlo para no dejar un hueco.
                        let url = await recorder.rotate()
                        Self.log.notice("trozo de audio \(url == nil ? "perdido" : "cerrado", privacy: .public); la grabación sigue")
                        onSegment(url)
                    }
                }
                try? await Task.sleep(for: .milliseconds(35))
            }
        }

        var lanes: [Lane] = []
        for (index, transcriber) in transcribers.enumerated() {
            let analyzer = SpeechAnalyzer(
                modules: [transcriber],
                options: .init(priority: .userInitiated, modelRetention: .processLifetime)
            )
            if !hints.isEmpty {
                let context = AnalysisContext()
                context.contextualStrings[.general] = hints
                do {
                    try await analyzer.setContext(context)
                } catch {
                    Self.log.error("el analizador no acepta el diccionario: \(error.localizedDescription, privacy: .public)")
                }
            }
            let transcript = Task {
                var scored = Scored()
                for try await result in transcriber.results {
                    scored.add(result.text)
                }
                return scored
            }
            lanes.append(Lane(locale: locales[index], analyzer: analyzer, input: feeds[index], transcript: transcript))
        }
        session = Session(capture: capture, lanes: lanes, pump: pump, meter: meter, counters: counters, recorder: recorder)

        do {
            for (lane, pair) in zip(lanes, pairs) {
                try await lane.analyzer.start(inputSequence: pair.stream)
            }
        } catch {
            Self.log.error("el analizador no arranca: \(error.localizedDescription, privacy: .public)")
            await cancel()
            throw error
        }
        Self.log.notice("analizador en marcha (\(clock.now - began, privacy: .public))")
    }

    func start(
        locale: Locale,
        hints: [String] = [],
        keepAudio: Bool = false,
        onLevel: @escaping @MainActor (Float) -> Void,
        onSegment: (@MainActor (URL?) -> Void)? = nil
    ) async throws {
        try await start(locales: [locale], hints: hints, keepAudio: keepAudio, onLevel: onLevel, onSegment: onSegment)
    }

    /// Para el micro, termina de procesar el audio pendiente y devuelve el texto (y el audio, si se pidió).
    /// `onAudio` recibe el audio en cuanto está cerrado, antes de que Apple termine: así Whisper empieza ya.
    /// Se le llama siempre: con nil si el archivo no se pudo cerrar, y con si hubo voz desde el último corte.
    func stop(onAudio: ((URL?, _ hasVoice: Bool) -> Void)? = nil) async throws -> Recording {
        guard let session else { throw Failure.notRunning }
        self.session = nil
        let clock = ContinuousClock()
        let began = clock.now
        // El medidor ya no debe cortar más trozos; si hay un corte a medias, se espera para no desordenarlos.
        session.meter.cancel()
        await rotation?.value
        rotation = nil
        // El archivo de audio se cierra antes de parar la captura, para que quede completo.
        let audioURL = await session.recorder?.finish()
        onAudio?(audioURL, voicedSinceCut >= 0.25)
        close(session)
        Self.log.notice("stop: \(session.counters.total) bloques de audio")
        // Si el reconocimiento de Apple falla, el dictado sigue con Whisper: no se pierde por eso.
        await withTaskGroup(of: Void.self) { group in
            for lane in session.lanes {
                let analyzer = lane.analyzer
                group.addTask {
                    do {
                        try await analyzer.finalizeAndFinishThroughEndOfInput()
                    } catch {
                        Self.log.error("el analizador no terminó bien: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }
        Self.log.notice("analizador terminado (\(clock.now - began, privacy: .public))")

        var best: (scored: Scored, locale: Locale)?
        for lane in session.lanes {
            guard let scored = try? await lane.transcript.value else { continue }
            Self.log.notice("\(lane.locale.identifier, privacy: .public): seguridad \(scored.averageConfidence, privacy: .public), \(scored.text.count) caracteres")
            // Gana el texto con más seguridad; uno vacío nunca gana a uno con texto.
            if let current = best, current.scored.characters > 0,
               scored.characters == 0 || scored.averageConfidence <= current.scored.averageConfidence {
                continue
            }
            best = (scored, lane.locale)
        }
        let text = best?.scored.text ?? ""
        Self.log.notice("texto: \(text.count) caracteres (\(clock.now - began, privacy: .public))")
        return Recording(transcript: text, audioURL: audioURL, locale: best?.locale)
    }

    func cancel() async {
        guard let session else { return }
        self.session = nil
        session.meter.cancel()
        rotation?.cancel()
        rotation = nil
        let audioURL = await session.recorder?.finish()
        close(session)
        for lane in session.lanes {
            lane.transcript.cancel()
            await lane.analyzer.cancelAndFinishNow()
        }
        Self.deleteAudio(audioURL)
    }

    static func deleteAudio(_ url: URL?) {
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    /// Corta en seco, sin esperar al analizador. Para cuando algo se ha atascado.
    func forceStop() {
        guard let session else { return }
        self.session = nil
        close(session)
        session.lanes.forEach { $0.transcript.cancel() }
        if let recorder = session.recorder {
            Task { Self.deleteAudio(await recorder.finish()) }
        }
        Self.log.error("parada forzosa")
    }

    private func close(_ session: Session) {
        session.meter.cancel()
        session.pump.cancel()
        session.lanes.forEach { $0.input.finish() }
        // `stopRunning` bloquea: fuera del hilo principal.
        let capture = Unchecked(session.capture)
        Task.detached { capture.value.stopRunning() }
    }

    // MARK: - Utilidades

    /// Prepara la captura fuera del hilo principal (`startRunning` bloquea).
    nonisolated private static func makeCapture(
        microphoneUID: String?,
        locales: [Locale],
        keepAudio: Bool
    ) async throws -> Unchecked<(CaptureInputSequenceProvider, [SpeechTranscriber], AudioFileRecorder?)> {
        guard let microphone = microphoneUID.flatMap({ AVCaptureDevice(uniqueID: $0) })
            ?? AVCaptureDevice.default(for: .audio)
        else { throw Failure.microphoneUnavailable }
        log.notice("start: idiomas \(locales.map(\.identifier).joined(separator: ", "), privacy: .public), micrófono \(microphone.localizedName, privacy: .public)")

        // Con la seguridad de cada palabra, para elegir idioma en el modo automático.
        let transcribers = locales.map {
            SpeechTranscriber(locale: $0, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.transcriptionConfidence])
        }
        let provider = try await CaptureInputSequenceProvider.providerWithSession(
            from: microphone,
            compatibleWith: transcribers,
            priority: .userInitiated
        )
        let session = provider.captureSession
        // Para Whisper: una salida más en la misma sesión que escribe el audio comprimido.
        var recorder: AudioFileRecorder?
        if keepAudio {
            let output = AVCaptureAudioFileOutput()
            session.beginConfiguration()
            if session.canAddOutput(output) {
                session.addOutput(output)
                recorder = AudioFileRecorder(output: output)
            } else {
                log.error("no se puede guardar el audio en esta sesión de captura")
            }
            session.commitConfiguration()
        }
        if !session.isRunning {
            session.startRunning()
        }
        recorder?.start()
        return Unchecked((provider, transcribers, recorder))
    }

    /// Volumen aproximado entre 0 y 1, para la onda del indicador.
    private static func normalized(decibels: Float) -> Float {
        min(max((decibels + 55) / 45, 0), 1)
    }
}

/// Graba el audio del dictado en m4a temporales (AAC, 16 kHz, mono), para enviarlo a Whisper.
/// Comprimido pesa unas 9 veces menos que un WAV y Groq responde de 2 a 4 veces antes.
/// En un dictado largo cambia de archivo sobre la marcha, sin perder audio entre uno y otro.
final class AudioFileRecorder: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    private struct State {
        var current: URL?
        var closed = false
        /// Archivos ya cerrados, por nombre: true si quedaron bien.
        var finished: [String: Bool] = [:]
    }

    private let output: AVCaptureAudioFileOutput
    private let state = OSAllocatedUnfairLock(initialState: State())
    /// Empezar, cambiar de archivo y parar no se pisan entre sí.
    private let gate = NSLock()

    init(output: AVCaptureAudioFileOutput) {
        self.output = output
        super.init()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 24_000,
        ]
    }

    private static func newURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "stepbro-\(UUID().uuidString).m4a")
    }

    func start() {
        gate.withLock {
            let url = Self.newURL()
            state.withLock { $0.current = url }
            output.startRecording(to: url, outputFileType: .m4a, recordingDelegate: self)
        }
    }

    /// Cierra el trozo en curso y sigue grabando en un archivo nuevo. Devuelve el trozo cerrado.
    func rotate() async -> URL? {
        let previous: URL? = gate.withLock {
            let next = Self.newURL()
            let previous: URL? = state.withLock { state in
                guard !state.closed, let current = state.current else { return nil }
                state.current = next
                return current
            }
            // Empezar otro archivo sin parar: AVFoundation no descarta audio entre los dos.
            if previous != nil {
                output.startRecording(to: next, outputFileType: .m4a, recordingDelegate: self)
            }
            return previous
        }
        guard let previous else { return nil }
        return await waitUntilFinished(previous)
    }

    /// Cierra el último archivo y devuelve su ruta, o nil si algo falló. Nunca espera más de 2 s.
    func finish() async -> URL? {
        let last: URL? = gate.withLock {
            let last: URL? = state.withLock { state in
                guard !state.closed else { return nil }
                state.closed = true
                return state.current
            }
            if last != nil { output.stopRecording() }
            return last
        }
        guard let last else { return nil }
        return await waitUntilFinished(last)
    }

    private func waitUntilFinished(_ url: URL) async -> URL? {
        let name = url.lastPathComponent
        for _ in 0..<200 {
            if let succeeded = state.withLock({ $0.finished[name] }) { return succeeded ? url : nil }
            try? await Task.sleep(for: .milliseconds(10))
        }
        SpeechEngine.log.error("el archivo de audio no se cerró a tiempo")
        return nil
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        // AVFoundation puede avisar de un "error" aunque el archivo haya quedado bien.
        let completed = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool
        let succeeded = error == nil || completed == true
        if let error, !succeeded {
            SpeechEngine.log.error("no se pudo guardar el audio: \(error.localizedDescription, privacy: .public)")
        }
        state.withLock { $0.finished[outputFileURL.lastPathComponent] = succeeded }
    }
}

/// Envoltorio para pasar entre hilos objetos de AVFoundation que no se declaran
/// Sendable. Solo se usa en momentos en que nadie más los está tocando.
struct Unchecked<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

/// Cuenta los bloques de audio que llegan del micrófono, para el diagnóstico.
final class AudioCounters: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: 0)

    var total: Int { state.withLock { $0 } }

    func count() {
        state.withLock { $0 += 1 }
    }
}

private extension String {
    mutating func appendSegment(_ segment: String) {
        guard !segment.isEmpty else { return }
        if let last, !last.isWhitespace, let first = segment.first, !first.isWhitespace {
            append(" ")
        }
        append(segment)
    }
}

extension Locale {
    var displayName: String {
        Locale.current.localizedString(forIdentifier: identifier)?.capitalized(with: .current) ?? identifier
    }
}
