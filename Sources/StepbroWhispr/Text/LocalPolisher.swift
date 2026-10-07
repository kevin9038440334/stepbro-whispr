import FoundationModels
import StepbroWhisprCore

/// Pulido con el modelo local de Apple Intelligence: quita muletillas y
/// arregla puntuación, mayúsculas y tildes, sin que el texto salga del Mac.
@MainActor
final class LocalPolisher {
    private let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
    private var warmSession: LanguageModelSession?
    /// Última respuesta descartada y el motivo; solo en memoria, para la autoprueba.
    private(set) var lastRejection: String?

    var isAvailable: Bool {
        if case .available = model.availability { true } else { false }
    }

    /// Explica por qué no se puede usar, o nil si está disponible.
    var unavailableReason: String? {
        switch model.availability {
        case .available:
            nil
        case .unavailable(.appleIntelligenceNotEnabled):
            "Activa Apple Intelligence en Ajustes del Sistema."
        case .unavailable(.deviceNotEligible):
            "Este Mac no es compatible con Apple Intelligence."
        case .unavailable(.modelNotReady):
            "El modelo de Apple Intelligence aún se está descargando."
        case .unavailable:
            "Apple Intelligence no está disponible."
        }
    }

    /// Se llama al empezar a grabar para que el modelo esté cargado al terminar.
    func prewarm() {
        guard isAvailable, warmSession == nil else { return }
        let session = makeSession()
        session.prewarm()
        warmSession = session
    }

    /// Devuelve el texto pulido, o nil si no merece la pena o no es fiable.
    /// Si el estilo pedido confunde al modelo, lo reintenta una vez con el estilo normal.
    func polish(_ input: PolishInput) async -> String? {
        // Frases muy cortas no merecen la espera.
        guard isAvailable, input.transcript.wordCount >= 4 else { return nil }
        if let result = await attempt(input) { return result }
        guard input.style != .normal, !Task.isCancelled else { return nil }
        var plain = input
        plain.style = .normal
        return await attempt(plain)
    }

    private func attempt(_ input: PolishInput) async -> String? {
        let session = warmSession ?? makeSession()
        warmSession = nil
        let prompt = PolishPrompt.context(for: input, includeLists: false) + "\n" + PolishPrompt.transcriptBlock(for: input)
        let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: input.transcript.count / 2 + 64)
        let work = Task {
            try await session.respond(to: prompt, options: options).content
        }
        let watchdog = Task {
            try await Task.sleep(for: .seconds(6))
            work.cancel()
        }
        defer { watchdog.cancel() }

        do {
            let output = try await withTaskCancellationHandler {
                try await work.value
            } onCancel: {
                work.cancel()
            }
            let cleaned = PolishGuard.sanitize(output)
            guard PolishGuard.isPlausibleLocal(cleaned, for: input.transcript) else {
                lastRejection = "poco fiable: \(cleaned)"
                return nil
            }
            guard PolishGuard.hasExpectedLanguage(cleaned, for: input) else {
                lastRejection = "otro idioma: \(cleaned)"
                return nil
            }
            lastRejection = nil
            return cleaned
        } catch {
            lastRejection = "error: \(error)"
            return nil
        }
    }

    private func makeSession() -> LanguageModelSession {
        LanguageModelSession(model: model, instructions: PolishPrompt.localInstructions)
    }
}
