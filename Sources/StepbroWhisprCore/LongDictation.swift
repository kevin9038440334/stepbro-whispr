import Foundation

/// Utilidades para dictados largos, que se transcriben y pulen por partes mientras se habla.
public enum LongDictation {
    /// Palabras que debe tener un bloque para pulirlo ya, sin esperar al final. Son bloques grandes:
    /// con más texto delante, el modelo entiende mejor de qué se habla y corrige mejor las palabras mal oídas.
    public static let blockWords = 220

    /// Separa un texto en lo que ya se puede pulir y su última frase, que se guarda:
    /// puede continuar en el trozo siguiente (el corte cae en una pausa, no siempre en un punto).
    public static func splitKeepingLastSentence(_ text: String) -> (ready: String, held: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var boundary: String.Index?
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let next = trimmed.index(after: index)
            if ".?!".contains(trimmed[index]), next < trimmed.endIndex, trimmed[next].isWhitespace,
               !trimmed[next...].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                boundary = next
            }
            index = next
        }
        guard let boundary else { return ("", trimmed) }
        return (
            String(trimmed[..<boundary]).trimmingCharacters(in: .whitespacesAndNewlines),
            String(trimmed[boundary...]).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Une dos trozos de transcripción. Si Whisper cerró con punto un trozo que seguía
    /// («Quiero que el agente.» + «pueda editar»), el modelo lo arregla al pulir: aquí solo se juntan.
    public static func join(_ first: String, _ second: String) -> String {
        let a = first.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = second.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + " " + b
    }

    /// Une los bloques ya pulidos: los elementos de una lista siguen en su propia línea.
    public static func joinPolished(_ blocks: [String]) -> String {
        var result = ""
        for block in blocks.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !block.isEmpty {
            let item = #"^(\d+[.)]|[-•])\s"#
            let lastLine = result.split(separator: "\n").last.map(String.init) ?? ""
            let afterItem = lastLine.range(of: item, options: .regularExpression) != nil
            let isItem = block.range(of: item, options: .regularExpression) != nil
            if result.isEmpty {
                result = block
            } else if isItem, afterItem || lastLine.hasSuffix(":") {
                result += "\n" + block
            } else if afterItem {
                // La lista se acabó: lo siguiente es texto normal, en su propio párrafo.
                result += "\n\n" + block
            } else if result.contains("\n\n") || block.contains("\n\n"), block.first?.isLowercase != true {
                // Si el texto ya va en párrafos, cada bloque nuevo empieza el suyo (salvo que continúe la frase).
                result += "\n\n" + block
            } else {
                result += " " + block
            }
        }
        return result
    }
}

/// Ajusta el dictado a lo que ya hay escrito antes del cursor.
public enum ContextJoiner {
    /// Si el texto de antes se quedó a media frase, el dictado la continúa en minúscula;
    /// si no acaba en espacio, se separa con uno.
    public static func adapt(_ text: String, after before: String?, keepingCase protected: [String] = []) -> String {
        guard let before, let last = before.last, !text.isEmpty else { return text }
        var result = text
        let ending = before.trimmingCharacters(in: .whitespacesAndNewlines).last
        if let ending, ending.isLetter || ending.isNumber || ",;".contains(ending), !before.hasSuffix("\n"),
           startsWithFunctionWord(result), !startsWithProperWord(result, protected: protected) {
            result = lowercasedFirst(result)
        }
        // Una lista empieza en su propia línea.
        if !before.hasSuffix("\n"), result.range(of: #"^(\d+[.)]|[-•])\s"#, options: .regularExpression) != nil {
            return "\n" + result
        }
        if !last.isWhitespace, !"([{«\"'¿¡/@#-_".contains(last), let first = result.first, !".,;:!?)".contains(first) {
            result = " " + result
        }
        return result
    }

    /// Palabras que nunca son un nombre propio: solo ante ellas se pasa a minúscula con seguridad
    /// («para que» + «Lo revises» sí; «hablé con» + «María» no).
    private static let functionWords: Set<String> = [
        "el", "la", "los", "las", "un", "una", "unos", "unas", "y", "e", "o", "u", "pero", "que", "porque", "para", "por",
        "con", "sin", "en", "de", "del", "al", "a", "se", "me", "te", "lo", "le", "les", "nos", "no", "si", "cuando", "como",
        "donde", "es", "está", "están", "son", "fue", "era", "hay", "ya", "también", "aunque", "mientras", "pues", "entonces",
        "luego", "después", "antes", "su", "sus", "mi", "mis", "tu", "tus", "esto", "eso", "este", "esta", "ese", "esa", "muy", "más",
        "the", "and", "but", "or", "to", "of", "in", "on", "at", "for", "with", "that", "it", "is", "are", "was", "so", "then", "because",
    ]

    private static func startsWithFunctionWord(_ text: String) -> Bool {
        let word = text.prefix { $0.isLetter }
        return functionWords.contains(word.lowercased())
    }

    /// La primera palabra debe conservar su mayúscula: sigla, «iPhone», «I», o un término del diccionario.
    private static func startsWithProperWord(_ text: String, protected: [String]) -> Bool {
        let word = text.drop { !$0.isLetter && !$0.isNumber }.prefix { $0.isLetter || $0.isNumber || $0 == "'" }
        guard let first = word.first, first.isUppercase else { return true }
        if word == "I" || word.hasPrefix("I'") { return true }
        if word.dropFirst().contains(where: \.isUppercase) { return true }
        let lowered = word.lowercased()
        return protected.contains { $0.lowercased().split(separator: " ").first.map(String.init) == lowered }
    }

    private static func lowercasedFirst(_ text: String) -> String {
        guard let index = text.firstIndex(where: \.isLetter) else { return text }
        // «¿Vienes?» sigue siendo una frase nueva: solo se toca si la letra es lo primero.
        guard index == text.startIndex else { return text }
        return text[index].lowercased() + text[text.index(after: index)...]
    }
}
