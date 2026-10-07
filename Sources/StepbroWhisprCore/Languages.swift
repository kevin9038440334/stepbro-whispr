import Foundation
import NaturalLanguage

/// Idioma al que traducir el dictado (o ninguno).
public enum TranslationTarget: String, CaseIterable, Identifiable, Codable, Sendable {
    case none = ""
    case spanish = "es"
    case english = "en"
    case french = "fr"
    case portuguese = "pt"
    case german = "de"
    case italian = "it"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: "No traducir"
        case .spanish: "Español"
        case .english: "Inglés"
        case .french: "Francés"
        case .portuguese: "Portugués"
        case .german: "Alemán"
        case .italian: "Italiano"
        }
    }

    /// Código de idioma, o nil si no hay que traducir.
    public var code: String? { self == .none ? nil : rawValue }
}

public enum Languages {
    /// Nombre en inglés de un idioma («es» → «Spanish»), que los modelos entienden mejor.
    public static func englishName(_ code: String) -> String {
        Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
    }

    /// Idioma dominante de un texto, eligiendo entre los indicados (o cualquiera si la lista está vacía).
    public static func dominant(_ text: String, among codes: [String] = []) -> String? {
        let recognizer = NLLanguageRecognizer()
        if !codes.isEmpty {
            recognizer.languageConstraints = codes.map { NLLanguage(rawValue: $0) }
        }
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    /// Idiomas de las frases de un texto (solo frases de dos o más palabras).
    public static func sentenceLanguages(_ text: String, among codes: [String]) -> Set<String> {
        let sentences = text.split(whereSeparator: { ".?!\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "¿¡"))) }
            .filter { $0.split(separator: " ").count >= 2 }
        return Set(sentences.compactMap { dominant($0, among: codes) })
    }

    /// ¿Está el texto escrito en ese idioma? Tolerante con frases cortas o mezcladas.
    public static func isWritten(in code: String, _ text: String) -> Bool {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let detected = recognizer.dominantLanguage, detected.rawValue != code else { return true }
        let confidence = recognizer.languageHypotheses(withMaximum: 5)[NLLanguage(rawValue: code)] ?? 0
        return confidence > 0.2
    }
}
