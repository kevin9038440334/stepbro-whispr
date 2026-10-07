import Foundation

/// Atajo de texto: al decir el disparador se escribe el texto completo.
public struct Snippet: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    /// Lo que dices ("mi correo").
    public var trigger: String
    /// Lo que se escribe ("kevin@ejemplo.com").
    public var expansion: String

    public init(id: UUID = UUID(), trigger: String, expansion: String) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
    }
}

public enum Snippets {
    /// Si todo el dictado es un disparador ("Mi correo."), devuelve su texto completo.
    public static func wholeMatch(for text: String, in snippets: [Snippet]) -> Snippet? {
        let spoken = normalized(text)
        guard !spoken.isEmpty else { return nil }
        return snippets.first { !normalized($0.trigger).isEmpty && normalized($0.trigger) == spoken }
    }

    /// Sustituye los disparadores que aparezcan dentro del texto.
    public static func expand(_ snippets: [Snippet], in text: String) -> String {
        if let whole = wholeMatch(for: text, in: snippets) {
            return whole.expansion
        }
        var result = text
        // Los disparadores largos primero, para que "mi correo del trabajo" gane a "mi correo".
        for snippet in snippets.sorted(by: { $0.trigger.count > $1.trigger.count }) {
            let trigger = snippet.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trigger.isEmpty, !snippet.expansion.isEmpty else { continue }
            result = Vocabulary.replaceWholeWords(trigger, with: snippet.expansion, in: result)
        }
        return result
    }

    /// ¿Está `text` entero dentro de `other`? Sin contar mayúsculas, tildes ni puntuación.
    public static func isContained(_ text: String, in other: String) -> Bool {
        let needle = normalized(text)
        return !needle.isEmpty && (" " + normalized(other) + " ").contains(" " + needle + " ")
    }

    /// Minúsculas, sin tildes, sin puntuación y con espacios simples.
    static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let letters = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(letters).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
