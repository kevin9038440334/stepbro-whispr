import Foundation

/// Una palabra del diccionario: cómo se escribe y, opcionalmente,
/// cómo la entiende mal el reconocimiento de voz.
public struct VocabularyEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    /// Forma correcta, tal cual debe escribirse ("stepbro", "iPhone", "Kubernetes").
    public var term: String
    /// Formas en que suele oírse mal ("estep bro", "step bro").
    public var heardAs: [String]
    /// Palabras corrientes que suenan igual y también se usan («cloud» para «Claude»): no se sustituyen;
    /// se le dan al reconocimiento como contrapeso y la IA elige una u otra por el contexto.
    public var confusedWith: [String]

    public init(id: UUID = UUID(), term: String, heardAs: [String] = [], confusedWith: [String] = []) {
        self.id = id
        self.term = term
        self.heardAs = heardAs
        self.confusedWith = confusedWith
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        term = try container.decode(String.self, forKey: .term)
        heardAs = try container.decodeIfPresent([String].self, forKey: .heardAs) ?? []
        confusedWith = try container.decodeIfPresent([String].self, forKey: .confusedWith) ?? []
    }
}

public enum Vocabulary {
    /// Corrige el texto con el diccionario: sustituye lo que se oyó mal y
    /// devuelve a cada término su forma exacta ("iphone" → "iPhone").
    public static func apply(_ entries: [VocabularyEntry], to text: String) -> String {
        var result = text
        for entry in entries {
            let term = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { continue }
            let variants = entry.heardAs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                // Las variantes largas primero, para que "step bro" no se coma parte de "estep bro".
                .sorted { $0.count > $1.count }
            for variant in variants {
                // Pegada («CloudCode») solo si es larga y no coincide con el propio término escrito normal.
                let glued = variant.filter { !$0.isWhitespace }
                let allowGlued = glued.count >= 6 && Snippets.normalized(glued) != Snippets.normalized(term)
                result = replaceWholeWords(variant, with: term, in: result, allowGlued: allowGlued)
            }
            // El propio término solo se recoloca en mayúsculas si está escrito normal: «claude-code» es un paquete.
            result = replaceWholeWords(term, with: term, in: result, allowHyphen: false)
        }
        return result
    }

    /// ¿Aparece en el texto un término que se confunde con una palabra corriente, o esa palabra?
    /// Entonces hace falta contexto para saber cuál de las dos se dijo.
    public static func hasAmbiguousWord(_ text: String, in entries: [VocabularyEntry]) -> Bool {
        let words = Set(Snippets.normalized(text).split(separator: " ").map(String.init))
        return entries.contains { entry in
            !entry.confusedWith.isEmpty
                && ([entry.term] + entry.confusedWith).contains { words.contains(Snippets.normalized($0)) }
        }
    }

    /// Reemplaza apariciones como palabra completa, sin distinguir mayúsculas ni tildes.
    /// No toca lo que forma parte de un nombre de archivo, una ruta, un enlace, un correo o un identificador
    /// («~/.claude/settings.json», «claude-code», «GROQ_API_KEY»).
    static func replaceWholeWords(
        _ phrase: String, with replacement: String, in text: String, allowGlued: Bool = false, allowHyphen: Bool = true
    ) -> String {
        let separator = allowGlued ? "(?:[ \\t]+|-|)" : allowHyphen ? "(?:[ \\t]+|-)" : "[ \\t]+"
        let pattern = #"(?<![\p{L}\p{N}_@./~-])"# + flexiblePattern(for: phrase, separator: separator)
            + #"(?![\p{L}\p{N}_]|[./@-][\p{L}\p{N}])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    /// Patrón que acepta la frase con o sin tildes y con las palabras separadas por espacios o un guion
    /// (nunca un salto de línea) y, si se permite, pegadas: el reconocimiento escribe «cloud code»,
    /// «cloud-code» o «CloudCode» según le da.
    private static func flexiblePattern(for phrase: String, separator: String) -> String {
        let words = phrase.split(whereSeparator: \.isWhitespace).map { word in
            word.map { character -> String in
                let base = String(character).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                if let variants = accentVariants[base] {
                    return "[" + variants + "]"
                }
                return NSRegularExpression.escapedPattern(for: String(character))
            }.joined()
        }
        return words.joined(separator: separator)
    }

    private static let accentVariants: [String: String] = [
        "a": "aáàäâ", "e": "eéèëê", "i": "iíìïî", "o": "oóòöô", "u": "uúùüû", "n": "nñ",
    ]
}
