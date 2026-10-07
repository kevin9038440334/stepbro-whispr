import Foundation
import Observation
import StepbroWhisprCore

/// Motor Groq: Whisper para transcribir y un modelo de texto para pulir.
/// Envía audio y texto a Groq; si falla o no hay conexión, se usa lo de tu Mac.
@MainActor
@Observable
final class GroqService {
    nonisolated private static let keyAccount = "groq-api-key"

    private(set) var hasKey = SecretStore.read(GroqService.keyAccount)?.isEmpty == false
    /// Último fallo, para enseñarlo en Ajustes.
    private(set) var lastError: String?
    /// Modelo que pulió el último dictado, para el banco de pruebas.
    @ObservationIgnored private(set) var lastPolishModel: GroqChatModel?

    init() {
        migrateKeyFromKeychain()
    }

    /// Las primeras versiones guardaban la clave en el Llavero. Se traslada una sola vez,
    /// fuera del hilo principal: macOS puede pedir permiso y no debe congelar la ventana.
    private func migrateKeyFromKeychain() {
        let flag = "groqKeyMigratedFromKeychain"
        guard !hasKey, !UserDefaults.standard.bool(forKey: flag) else { return }
        UserDefaults.standard.set(true, forKey: flag)
        Task.detached(priority: .utility) { [weak self] in
            guard let key = LegacyKeychain.read(GroqService.keyAccount) else { return }
            await self?.setKey(key)
        }
    }

    /// Groq se usa cuando es el motor elegido y hay clave; si no, todo va con Apple.
    var isActive: Bool { Preferences.engine == .groq && hasKey }
    var transcribes: Bool { isActive }
    var polishes: Bool { isActive }

    /// El banco de pruebas puede forzar otro modelo con SUSURRO_GROQ_MODEL.
    private var chatModel: GroqChatModel {
        ProcessInfo.processInfo.environment["SUSURRO_GROQ_MODEL"].flatMap(GroqChatModel.init) ?? Preferences.groqChatModel
    }

    // MARK: - Límites

    /// Lo que le queda a un modelo de su límite por minuto, según su última respuesta.
    private struct Budget {
        var limit = GroqRateLimit()
        var measuredAt = Date.distantPast
        /// Tras un «límite alcanzado» o un fallo del modelo, no se le pide nada hasta entonces.
        var blockedUntil = Date.distantPast
    }

    @ObservationIgnored private var budgets: [GroqChatModel: Budget] = [:]
    /// Sin conexión o Groq caído: durante unos segundos no se le espera.
    @ObservationIgnored private var offlineUntil = Date.distantPast
    /// El límite de Whisper va aparte del de los modelos de texto.
    @ObservationIgnored private var whisperBlockedUntil = Date.distantPast
    @ObservationIgnored private var lastWarmUp = Date.distantPast
    @ObservationIgnored private var networkFailed = false

    /// La red va a trompicones: durante unos segundos se le da menos margen al pulido.
    @ObservationIgnored private var slowUntil = Date.distantPast

    /// Whisper no ha llegado a tiempo: el dictado sigue con lo que oyó Apple y sin esperas largas.
    func noteSlowNetwork() {
        slowUntil = .now.addingTimeInterval(10)
    }

    /// ¿Merece la pena esperar a Whisper ahora mismo?
    var canTranscribe: Bool {
        transcribes && Date.now >= offlineUntil && Date.now >= whisperBlockedUntil
    }

    private func canAfford(_ model: GroqChatModel, tokens: Int) -> Bool {
        guard let budget = budgets[model] else { return true }
        guard Date.now >= budget.blockedUntil else { return false }
        guard let available = budget.limit.available(after: Date.now.timeIntervalSince(budget.measuredAt)) else { return true }
        return available >= tokens
    }

    private func note(_ limit: GroqRateLimit, for model: GroqChatModel) {
        budgets[model, default: Budget()].limit = limit
        budgets[model, default: Budget()].measuredAt = .now
    }

    private func noteFailure(_ error: Error, model: GroqChatModel) {
        switch error as? GroqError {
        case .rateLimited(let retryAfter):
            budgets[model, default: Budget()].blockedUntil = .now.addingTimeInterval(min(60, max(2, retryAfter ?? 20)))
        case .overloaded, .emptyResponse, .truncated, .server:
            budgets[model, default: Budget()].blockedUntil = .now.addingTimeInterval(30)
        case .network:
            offlineUntil = .now.addingTimeInterval(10)
        default:
            // Una respuesta lenta suelta no dice nada del siguiente dictado.
            break
        }
    }

    /// Abre la conexión con Groq mientras hablas, para que al terminar no haya que esperarla.
    func warmUp() {
        guard isActive, Date.now.timeIntervalSince(lastWarmUp) > 20,
              let key = SecretStore.read(Self.keyAccount)
        else { return }
        lastWarmUp = .now
        for session in [GroqClient.primarySession, GroqClient.backupSession] {
            Task.detached(priority: .userInitiated) {
                try? await GroqClient(apiKey: key, timeout: 5, session: session).validateKey()
            }
        }
    }

    // MARK: - Clave

    func setKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        SecretStore.save(trimmed, for: Self.keyAccount)
        hasKey = !trimmed.isEmpty
        lastError = nil
    }

    func removeKey() {
        SecretStore.delete(Self.keyAccount)
        hasKey = false
    }

    /// Comprueba una clave sin gastar nada. Devuelve el error, o nil si funciona.
    func test(key: String) async -> String? {
        do {
            try await GroqClient(apiKey: key, timeout: 15).validateKey()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func testSavedKey() async -> String? {
        guard let key = SecretStore.read(Self.keyAccount) else { return GroqError.missingKey.localizedDescription }
        return await test(key: key)
    }

    /// Lo que puede pasar mientras se espera una respuesta de Groq.
    private enum Event: Sendable {
        case answer(String?)
        /// El modelo contestó, pero su texto no es de fiar: otro modelo no lo haría mejor.
        case rejected
        /// Va lento: toca repetir la petición por otro lado.
        case hedge
        case deadline
    }

    // MARK: - Transcripción

    /// Devuelve lo que entendió Whisper, o nil si falla.
    /// `language`: código del idioma, o nil para que Whisper lo detecte (y entienda mezclas).
    /// Si la respuesta tarda más de lo normal, la petición se repite por otra conexión y vale la primera que llegue.
    /// `previous`: lo dicho justo antes (en un dictado largo), para que Whisper escriba igual los mismos términos.
    func transcribe(
        audioURL: URL, language: String?, hints: [String], previous: String? = nil, timeout: TimeInterval = 6
    ) async -> String? {
        guard canTranscribe, let key = SecretStore.read(Self.keyAccount),
              let audio = try? Data(contentsOf: audioURL), !audio.isEmpty
        else { return nil }
        let filename = audioURL.lastPathComponent
        // Sin idioma fijo, una pista bilingüe anima a Whisper a respetar cada idioma.
        var hint = language == nil
            ? "Hola, ¿qué tal? Hi, how are you? " + (TranscriptChooser.prompt(for: hints) ?? "")
            : TranscriptChooser.prompt(for: hints)
        if let previous, !previous.isEmpty {
            // Whisper solo mira el final de la pista: lo anterior va lo último.
            hint = [hint, String(previous.suffix(300))].compactMap { $0 }.joined(separator: " ")
        }
        let prompt = hint
        // Lo normal son 0,3–0,5 s; el audio pesa unos 3 KB por segundo y uno largo tarda algo más.
        let patience = 0.9 + Double(audio.count) / 3000 * 0.03
        return await withTaskGroup(of: Event.self) { group in
            var running = 0
            func launch(_ session: URLSession) {
                running += 1
                group.addTask {
                    .answer(await self.attemptTranscription(
                        audio: audio, filename: filename, language: language, prompt: prompt,
                        key: key, timeout: timeout, session: session
                    ))
                }
            }
            networkFailed = false
            launch(GroqClient.primarySession)
            group.addTask {
                try? await Task.sleep(for: .milliseconds(Int(patience * 1000)))
                return .hedge
            }
            // El plazo de la petición solo cuenta el tiempo sin recibir nada: este es el tope de verdad.
            group.addTask {
                try? await Task.sleep(for: .milliseconds(Int((timeout + patience) * 1000)))
                return .deadline
            }
            defer { group.cancelAll() }
            var hedged = false
            for await event in group {
                guard !Task.isCancelled else { return nil }
                switch event {
                case .answer(let text?):
                    return text
                case .answer(nil):
                    running -= 1
                    // Un fallo de red se reintenta por la segunda conexión; un límite alcanzado, no.
                    if !hedged, Date.now >= whisperBlockedUntil {
                        hedged = true
                        launch(GroqClient.backupSession)
                    } else if running == 0 {
                        if networkFailed { offlineUntil = .now.addingTimeInterval(10) }
                        return nil
                    }
                case .hedge:
                    if !hedged {
                        hedged = true
                        SpeechEngine.log.notice("Whisper va lento: se repite por la segunda conexión")
                        launch(GroqClient.backupSession)
                    }
                case .deadline:
                    SpeechEngine.log.error("Whisper no ha contestado a tiempo")
                    return nil
                case .rejected:
                    break
                }
            }
            return nil
        }
    }

    private func attemptTranscription(
        audio: Data, filename: String, language: String?, prompt: String?,
        key: String, timeout: TimeInterval, session: URLSession
    ) async -> String? {
        do {
            let text = try await GroqClient(apiKey: key, timeout: timeout, session: session).transcribe(
                audio: audio,
                filename: filename,
                model: Preferences.groqWhisperModel,
                language: language,
                prompt: prompt
            )
            lastError = nil
            return text
        } catch is CancellationError {
            return nil
        } catch {
            lastError = error.localizedDescription
            switch error as? GroqError {
            case .rateLimited(let retryAfter):
                whisperBlockedUntil = .now.addingTimeInterval(min(60, max(2, retryAfter ?? 20)))
            case .network:
                // Solo se da la red por caída si también falla la segunda conexión.
                networkFailed = true
            default:
                break
            }
            SpeechEngine.log.error("Whisper (Groq) falló: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Pulido

    /// ¿Hay algún modelo con margen para pulir este texto ahora mismo?
    func canPolish(_ input: PolishInput) -> Bool {
        polishes && Date.now >= offlineUntil && !candidates(for: input).isEmpty
    }

    private func cost(of input: PolishInput) -> Int {
        GroqClient.estimatedTokens(PolishPrompt.smartInstructions)
            + GroqClient.estimatedTokens(PolishPrompt.smartMessage(for: input))
            + GroqClient.estimatedTokens(input.transcript) + 120
    }

    /// El modelo elegido y, de reserva, los demás; solo los que tienen margen en su límite.
    private func candidates(for input: PolishInput) -> [GroqChatModel] {
        let tokens = cost(of: input)
        let text = GroqClient.estimatedTokens(input.transcript)
        return chatModel.withFallbacks.filter { $0.outputBudget(forTextOf: text) != nil && canAfford($0, tokens: tokens) }
    }

    /// Devuelve el texto pulido, o nil si falla o tarda demasiado (y entonces se pega la transcripción limpia).
    /// Si el modelo elegido va lento o ha llegado a su límite, se le pide a otro: cada uno tiene el suyo.
    func polish(_ input: PolishInput) async -> String? {
        guard polishes, Date.now >= offlineUntil, let key = SecretStore.read(Self.keyAccount) else { return nil }
        var waiting = candidates(for: input)[...]
        guard let first = waiting.popFirst() else {
            SpeechEngine.log.notice("Groq: todos los modelos de texto están en su límite; se pega sin pulir")
            return nil
        }
        // Lo normal es medio segundo; un texto largo necesita más para escribirse entero.
        let deadline = Date.now < slowUntil ? 2 : min(8, 2.5 + Double(input.transcript.wordCount) / 60)
        return await withTaskGroup(of: Event.self) { group in
            var running = 0
            var launched = 0
            func launch(_ model: GroqChatModel) {
                running += 1
                // La primera petición va por la conexión habitual; las de refuerzo, por la segunda.
                let session = launched == 0 ? GroqClient.primarySession : GroqClient.backupSession
                launched += 1
                group.addTask { await self.attempt(model, input: input, key: key, timeout: deadline, session: session) }
            }
            launch(first)
            group.addTask {
                try? await Task.sleep(for: .milliseconds(1000))
                return .hedge
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(Int(deadline * 1000)))
                return .deadline
            }
            defer { group.cancelAll() }
            for await event in group {
                guard !Task.isCancelled else { return nil }
                switch event {
                case .answer(let text?):
                    return text
                case .answer(nil):
                    running -= 1
                    if let next = waiting.popFirst() {
                        launch(next)
                    } else if running == 0 {
                        return nil
                    }
                case .hedge:
                    // Va lento: se pregunta también a otro modelo y vale el primero que conteste.
                    if let next = waiting.popFirst() { launch(next) }
                case .rejected:
                    return nil
                case .deadline:
                    SpeechEngine.log.error("Groq no ha pulido a tiempo")
                    return nil
                }
            }
            return nil
        }
    }

    private func attempt(
        _ model: GroqChatModel, input: PolishInput, key: String, timeout: TimeInterval, session: URLSession
    ) async -> Event {
        do {
            let reply = try await GroqClient(apiKey: key, timeout: timeout, session: session).complete(
                model: model,
                system: PolishPrompt.smartInstructions,
                user: PolishPrompt.smartMessage(for: input),
                maxTokens: model.outputBudget(forTextOf: GroqClient.estimatedTokens(input.transcript)) ?? 4096
            )
            note(reply.limit, for: model)
            lastError = nil
            let cleaned = PolishGuard.removingEcho(of: input.textBefore, from: PolishGuard.sanitize(reply.text), transcript: input.transcript)
            let sources = [input.transcript, input.alternative ?? "", input.textBefore ?? ""] + input.vocabulary
            // Con una o dos palabras no se puede saber el idioma: la comprobación solo vale con frases.
            let languageOK = (input.translateTo == nil && input.transcript.wordCount < 4)
                || PolishGuard.hasExpectedLanguage(cleaned, for: input)
            guard input.translateTo != nil
                || (PolishGuard.isPlausibleCloud(cleaned, for: input.transcript) && PolishGuard.isFaithful(cleaned, to: sources)),
                languageOK
            else {
                SpeechEngine.log.error("\(model.rawValue, privacy: .public) devolvió un texto poco fiable; se descarta")
                return .rejected
            }
            lastPolishModel = model
            return .answer(cleaned)
        } catch is CancellationError {
            return .answer(nil)
        } catch {
            lastError = error.localizedDescription
            noteFailure(error, model: model)
            SpeechEngine.log.error("\(model.rawValue, privacy: .public) falló: \(error.localizedDescription, privacy: .public)")
            return .answer(nil)
        }
    }
}
