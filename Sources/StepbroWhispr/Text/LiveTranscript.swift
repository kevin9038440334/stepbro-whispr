import Foundation
import StepbroWhisprCore

/// Un dictado largo, transcrito y pulido por partes mientras sigues hablando:
/// al soltar la tecla solo queda por hacer el último trozo, dure lo que dure el dictado.
@MainActor
final class LiveTranscript {
    private struct State {
        /// Bloques ya pulidos, en orden.
        var polished: [String] = []
        /// Transcripción aún sin pulir: la última frase se guarda por si continúa en el trozo siguiente.
        var pending = ""
        var translated = true
        /// Algún trozo no se pudo transcribir: el dictado entero se hará con lo que oyó Apple.
        var failed = false
    }

    private let groq: GroqService
    private let processor: TextProcessor
    private let job: Task<TextProcessor.Job, Never>
    private let language: String?
    private let hints: [String]
    private var chain: Task<State, Never>
    /// Todas las tareas en marcha, para cancelarlas de golpe (y no seguir gastando el límite de Groq).
    private var tasks: [Task<Void, Never>] = []
    /// Un trozo se perdió o no se pudo transcribir: los siguientes ya no se envían.
    private var failed = false
    /// Lo último que entendió Whisper, para que el trozo siguiente escriba igual los mismos términos.
    private var latestRaw = ""
    private(set) var segments = 0

    init(groq: GroqService, processor: TextProcessor, job: Task<TextProcessor.Job, Never>, language: String?, hints: [String]) {
        self.groq = groq
        self.processor = processor
        self.job = job
        self.language = language
        self.hints = hints
        chain = Task { State() }
    }

    /// Un trozo de audio ya cerrado (nil si se perdió); la grabación sigue.
    func add(_ url: URL?) {
        segments += 1
        guard let url else {
            failed = true
            return
        }
        chain = step(url, isLast: false, onPolishing: {})
    }

    /// El último trozo. Devuelve el texto final, o nil si hay que recurrir a la transcripción de Apple.
    /// `hasVoice`: si se habló desde el último corte. Si no, el trozo es silencio y Whisper se lo inventaría.
    func finish(lastURL: URL?, hasVoice: Bool, onPolishing: @escaping @MainActor () -> Void) async -> String? {
        var lastURL = lastURL
        if !hasVoice {
            SpeechEngine.deleteAudio(lastURL)
            lastURL = nil
        } else if lastURL == nil {
            // Había voz pero el archivo no se cerró: falta el final.
            failed = true
        }
        chain = step(lastURL, isLast: true, onPolishing: onPolishing)
        let state = await chain.value
        guard !state.failed, !failed, !Task.isCancelled else {
            if !Task.isCancelled { groq.noteSlowNetwork() }
            return nil
        }
        let text = LongDictation.joinPolished(state.polished)
        guard !text.isEmpty else { return nil }
        let job = await job.value
        return await processor.finish(text, translated: state.translated && job.translateTo != nil, job: job, onPolishing: onPolishing)
    }

    func cancel() {
        failed = true
        chain.cancel()
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    /// Espera a que los trozos entregados estén procesados (para el banco de pruebas).
    func settle() async {
        _ = await chain.value
    }

    private func step(_ url: URL?, isLast: Bool, onPolishing: @escaping @MainActor () -> Void) -> Task<State, Never> {
        let previous = chain
        // Whisper empieza ya, sin esperar a que terminen los trozos anteriores.
        let whisper = Task { await transcribe(url, isLast: isLast) }
        tasks.append(Task { _ = await whisper.value })
        let step = Task {
            var state = await withTaskCancellationHandler { await previous.value } onCancel: { previous.cancel() }
            let heard = await withTaskCancellationHandler { await whisper.value } onCancel: { whisper.cancel() }
            guard let text = heard, !state.failed, !Task.isCancelled else {
                state.failed = true
                self.failed = true
                return state
            }
            state.pending = LongDictation.join(state.pending, text)
            let (ready, held) = isLast ? (state.pending, "") : LongDictation.splitKeepingLastSentence(state.pending)
            guard isLast || ready.wordCount >= LongDictation.blockWords else { return state }
            state.pending = held
            guard !ready.isEmpty else { return state }
            let job = await job.value
            // Cada bloque continúa el anterior (o lo que ya había escrito en el campo).
            let before = state.polished.isEmpty ? job.context.textBefore : state.polished.last
            let refined = await processor.refine(ready, job: job, textBefore: before, onPolishing: onPolishing)
            state.polished.append(refined.text)
            state.translated = state.translated && refined.translated
            return state
        }
        return step
    }

    /// Lo que entendió Whisper de un trozo («» si era silencio), o nil si falla.
    private func transcribe(_ url: URL?, isLast: Bool) async -> String? {
        guard let url else { return "" }
        defer { SpeechEngine.deleteAudio(url) }
        guard !failed else { return nil }
        // Mientras se sigue hablando no hay prisa; al final, sí.
        let previous = latestRaw
        guard let text = await groq.transcribe(
            audioURL: url, language: language, hints: hints, previous: previous, timeout: isLast ? 4 : 10
        ) else { return nil }
        // Los trozos sin voz no llegan hasta aquí, así que una frase corta («Muchas gracias.») es de verdad.
        latestRaw = text
        return text
    }
}
