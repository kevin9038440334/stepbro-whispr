import AppKit
import StepbroWhisprCore

/// App donde se va a pegar el dictado, capturada al empezar a grabar.
struct DictationTarget: Sendable {
    let appName: String?
    let bundleID: String?

    var category: AppCategory { AppCategory(bundleID: bundleID) }

    /// La app que tiene el foco, salvo que sea la propia stepbro whispr.
    static func frontmost() -> DictationTarget {
        let app = NSWorkspace.shared.frontmostApplication
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return DictationTarget(appName: nil, bundleID: nil)
        }
        return DictationTarget(appName: app.localizedName, bundleID: app.bundleIdentifier)
    }
}

/// Lo que ya hay escrito donde se va a pegar el dictado.
struct DictationContext: Sendable {
    /// Texto justo antes del cursor, si la app deja leerlo.
    var textBefore: String?
    /// El dictado anterior en la misma app, si es reciente.
    var previousDictation: String?

    static let none = DictationContext()
}

/// Convierte la transcripción en el texto final:
/// diccionario → atajo completo → formato instantáneo → IA solo si hace falta → retoques → atajos → estilo.
@MainActor
final class TextProcessor {
    /// Todo lo que se decide una vez por dictado, para pulirlo entero o por partes.
    struct Job {
        let entries: [VocabularyEntry]
        let snippets: [Snippet]
        let style: WritingStyle
        let locale: Locale
        let languages: [String]
        let translateTo: String?
        let target: DictationTarget
        let context: DictationContext

        var mixed: Bool { languages.count > 1 }
    }

    let local = LocalPolisher()
    let translator = AppleTranslator()
    let groq: GroqService
    let vocabulary: VocabularyStore

    init(vocabulary: VocabularyStore, groq: GroqService) {
        self.vocabulary = vocabulary
        self.groq = groq
    }

    var canPolish: Bool { groq.polishes || local.isAvailable }

    /// Carga el modelo local mientras se habla, si va a hacer falta.
    func prepare() {
        if Preferences.polish, !groq.polishes { local.prewarm() }
    }

    /// `languages`: idiomas posibles del dictado (dos en el modo automático).
    func makeJob(locale: Locale, languages: [String]? = nil, target: DictationTarget, context: DictationContext = .none) -> Job {
        Job(
            entries: vocabulary.entries,
            snippets: vocabulary.snippets,
            style: vocabulary.style(for: target.category),
            locale: locale,
            languages: languages ?? [locale.language.languageCode?.identifier].compactMap { $0 },
            translateTo: Preferences.translateTo.code,
            target: target,
            context: context
        )
    }

    /// `alternative`: la otra transcripción del mismo audio, para que la IA elija lo mejor de cada una.
    func process(
        _ raw: String,
        alternative: String? = nil,
        locale: Locale,
        languages: [String]? = nil,
        target: DictationTarget,
        context: DictationContext = .none,
        onPolishing: () -> Void
    ) async -> String {
        let job = makeJob(locale: locale, languages: languages, target: target, context: context)
        // Si todo el dictado es un atajo, se escribe tal cual, sin pasar por la IA.
        if let snippet = Snippets.wholeMatch(for: Vocabulary.apply(job.entries, to: raw), in: job.snippets) {
            return snippet.expansion
        }
        let refined = await refine(raw, alternative: alternative, job: job, textBefore: job.context.textBefore, onPolishing: onPolishing)
        return await finish(refined.text, translated: refined.translated, job: job, onPolishing: onPolishing)
    }

    /// Primera mitad: limpia una transcripción (entera o un bloque de un dictado largo), con IA si hace falta.
    /// `textBefore`: lo que va justo delante de este texto (el campo, o los bloques anteriores).
    func refine(
        _ raw: String,
        alternative: String? = nil,
        job: Job,
        textBefore: String?,
        onPolishing: () -> Void
    ) async -> (text: String, translated: Bool) {
        // Traducir solo si de verdad cambia el idioma.
        let spoken = job.mixed ? Languages.dominant(raw, among: job.languages) : job.languages.first
        let translateTo = job.translateTo.flatMap { $0 == spoken && !job.mixed ? nil : $0 }

        // Si se mezclan idiomas y Whisper ha traducido una parte, manda lo que oyó Apple.
        let choice = TranscriptChooser.preferOriginalLanguages(primary: raw, alternative: alternative, among: job.languages)
        // La versión traducida de Whisper no se pasa a la IA: la confundiría.
        let alternative = choice.swapped ? nil : choice.alternative
        var text = Vocabulary.apply(job.entries, to: choice.primary)
        guard Preferences.polish else { return (text, false) }

        // Formato instantáneo: comandos dictados, correos, repeticiones.
        text = SmartFormatter.prepare(text)
        let other = alternative.map { SmartFormatter.prepare(Vocabulary.apply(job.entries, to: $0)) }

        // La IA solo cuando hace falta: si el texto ya está limpio, se pega al instante.
        var polished = false
        var translated = false
        // Con Groq, la traducción va en el mismo paso que el pulido: no añade espera.
        let groqTranslates = translateTo != nil && groq.polishes
        // Si manda la versión de Apple por una mezcla de idiomas, la IA corrige sus palabras sueltas.
        // También si hay una palabra que se confunde con otra («Claude» y «cloud») y contexto para decidir.
        let ambiguous = text.wordCount >= 3 && Vocabulary.hasAmbiguousWord(text, in: job.entries)
        if canPolish, groqTranslates || choice.swapped || ambiguous || SmartFormatter.needsLanguageModel(text, alternative: other) {
            var input = PolishInput(
                transcript: text,
                alternative: other,
                locale: job.locale,
                style: job.style,
                appName: job.target.appName,
                vocabulary: job.entries.map(\.term),
                protectedPhrases: job.snippets.map(\.trigger),
                translateTo: translateTo,
                mixedLanguages: job.mixed
            )
            input.textBefore = textBefore
            input.previousDictation = job.context.previousDictation
            if groq.polishes {
                // Con Groq no se recurre al modelo de Apple si falla: tarda segundos,
                // y la transcripción de Whisper ya viene puntuada.
                if groq.canPolish(input) {
                    onPolishing()
                    if let result = await groq.polish(input) {
                        text = result
                        polished = true
                        translated = translateTo != nil
                    }
                }
            } else {
                onPolishing()
                // El modelo de Apple no traduce bien: solo pule, y traduce después la traducción de Apple.
                input.translateTo = nil
                if let result = await local.polish(input) {
                    text = result
                    polished = true
                }
            }
        }
        if !polished {
            text = BasicCleanup.apply(text, style: job.style)
        }
        return (text, translated)
    }

    /// Segunda mitad, sobre el texto completo: traducción pendiente, listas, signos, diccionario, atajos y estilo.
    func finish(_ refined: String, translated: Bool, job: Job, onPolishing: () -> Void) async -> String {
        var text = refined
        var translated = translated
        guard Preferences.polish else {
            return StyleFormatter.finish(Snippets.expand(job.snippets, in: text), style: job.style)
        }
        let spoken = job.mixed ? Languages.dominant(text, among: job.languages) : job.languages.first
        if let translateTo = job.translateTo, !translated, translateTo != spoken || job.mixed, !Task.isCancelled {
            onPolishing()
            if let result = await translator.translate(text, from: spoken, to: translateTo) {
                text = result
                translated = true
            }
        }

        // Retoques instantáneos: listas, ¿¡, preguntas evidentes, mayúsculas, espacios.
        let finalLanguages = translated ? [job.translateTo].compactMap { $0 } : job.languages
        text = SmartFormatter.finish(text, languages: finalLanguages)
        // El diccionario se aplica otra vez por si el modelo cambió alguna palabra.
        text = Vocabulary.apply(job.entries, to: text)
        text = Snippets.expand(job.snippets, in: text)
        return StyleFormatter.finish(text, style: job.style)
    }
}
