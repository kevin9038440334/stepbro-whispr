import Foundation

/// Elige entre la transcripción de Whisper (Groq) y la de Apple, que se hacen a la vez.
public enum TranscriptChooser {
    /// Frases que Whisper se inventa cuando hay silencio o ruido.
    static let hallucinations: Set<String> = [
        "gracias", "gracias por ver", "gracias por ver el video", "gracias por ver el video hasta el final",
        "muchas gracias", "suscribete", "suscribete al canal", "hasta la proxima",
        "subtitulos realizados por la comunidad de amara org", "subtitulado por la comunidad de amara org",
        "thank you", "thank you for watching", "thanks for watching", "subtitles by the amara org community",
        "you", "bye",
    ]

    public static func choose(whisper: String?, local: String) -> String {
        let local = local.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let whisper = whisper?.trimmingCharacters(in: .whitespacesAndNewlines), !whisper.isEmpty else {
            return local
        }
        let invented = isHallucination(whisper)
        // Apple no oyó nada: si Whisper suelta una frase típica de silencio, no se habló.
        if local.isEmpty {
            return invented ? "" : whisper
        }
        if invented {
            // Si Apple oyó casi lo mismo («muchas gracia»), se dijo de verdad, y Whisper lo escribe mejor.
            let heard = Snippets.normalized(local), said = Snippets.normalized(whisper)
            return heard.prefix(4) == said.prefix(4) && abs(heard.count - said.count) <= 3 ? whisper : local
        }
        // Mucho más largo que lo que oyó Apple: probablemente inventado.
        if whisper.count > local.count * 3 + 60 {
            return local
        }
        return strippingTrailingHallucination(whisper, reference: local)
    }

    /// Varios segundos de grabación en los que Apple no entendió ni una palabra: era ruido,
    /// y lo que traiga Whisper se lo ha inventado.
    public static func wasOnlyNoise(local: String, seconds: TimeInterval) -> Bool {
        // Con una o dos letras («Sí», «Ok») puede ser una respuesta corta tras pensarlo: se exige más silencio.
        let heard = Snippets.normalized(local).count
        return heard == 0 ? seconds >= 6 : heard < 3 && seconds >= 12
    }

    /// Con silencio al final, Whisper añade una despedida («Gracias.») que nadie dijo.
    /// Se quita si lo que oyó Apple no termina igual.
    public static func strippingTrailingHallucination(_ text: String, reference: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // La última frase: lo que va tras el último punto, interrogación o exclamación que no cierra el texto.
        let body = trimmed.dropLast()
        guard let cut = body.lastIndex(where: { ".?!\n".contains($0) }) else { return text }
        let last = String(trimmed[trimmed.index(after: cut)...])
        guard isHallucination(last) else { return text }
        let spoken = Snippets.normalized(reference)
        guard !spoken.isEmpty, !spoken.hasSuffix(Snippets.normalized(last)) else { return text }
        // Si Apple oyó más palabras que las del cuerpo, algo se dijo al final aunque lo entendiera mal («mucha gracia»).
        let kept = String(trimmed[...cut])
        guard spoken.split(separator: " ").count <= Snippets.normalized(kept).split(separator: " ").count else { return text }
        return kept
    }

    /// En dictados con varios idiomas, Whisper a veces traduce una parte al idioma del resto.
    /// Si la transcripción de Apple conserva más idiomas, manda Apple y Whisper queda de segunda opinión.
    public static func preferOriginalLanguages(
        primary: String,
        alternative: String?,
        among codes: [String]
    ) -> (primary: String, alternative: String?, swapped: Bool) {
        guard codes.count > 1, let alternative, !alternative.isEmpty else { return (primary, alternative, false) }
        let primaryLanguages = Languages.sentenceLanguages(primary, among: codes)
        let alternativeLanguages = Languages.sentenceLanguages(alternative, among: codes)
        guard alternativeLanguages.count > primaryLanguages.count else { return (primary, alternative, false) }
        return (alternative, primary, true)
    }

    public static func isHallucination(_ text: String) -> Bool {
        let normalized = Snippets.normalized(text)
        return hallucinations.contains(normalized) || normalized.hasPrefix("subtitulos realizados por")
    }

    /// Pista de ortografía para Whisper con las palabras del diccionario (máx. ~224 tokens).
    public static func prompt(for terms: [String]) -> String? {
        let unique = Array(NSOrderedSet(array: terms.filter { !$0.isEmpty })) as? [String] ?? []
        guard !unique.isEmpty else { return nil }
        var prompt = ""
        for term in unique {
            let next = prompt.isEmpty ? term : prompt + ", " + term
            if next.count > 600 { break }
            prompt = next
        }
        return prompt + "."
    }
}
