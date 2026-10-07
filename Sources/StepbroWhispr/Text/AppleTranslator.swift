import Foundation
import Observation
import StepbroWhisprCore
import Translation

/// Traducción de Apple, en el Mac y sin internet (motor Apple, o si Groq falla).
/// Necesita los idiomas descargados; Ajustes ofrece descargarlos.
@MainActor
@Observable
final class AppleTranslator {
    /// Último fallo, para enseñarlo en Ajustes.
    private(set) var lastError: String?

    func status(from source: String, to target: String) async -> LanguageAvailability.Status {
        await LanguageAvailability().status(from: Locale.Language(identifier: source), to: Locale.Language(identifier: target))
    }

    /// Devuelve el texto traducido, o nil si no se puede (idioma sin descargar, error…).
    func translate(_ text: String, from source: String?, to target: String) async -> String? {
        let source = source ?? Languages.dominant(text) ?? target
        guard source != target else { return text }
        guard await status(from: source, to: target) == .installed else {
            lastError = "Falta descargar \(Languages.englishName(source)) → \(Languages.englishName(target)) para traducir en tu Mac."
            return nil
        }
        do {
            let session = TranslationSession(
                installedSource: Locale.Language(identifier: source),
                target: Locale.Language(identifier: target)
            )
            let response = try await session.translate(text)
            lastError = nil
            return response.targetText
        } catch {
            lastError = error.localizedDescription
            SpeechEngine.log.error("traducción de Apple falló: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
