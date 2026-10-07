import Foundation

/// Limpieza sin IA: el mínimo garantizado cuando el pulido no está disponible o falla.
public enum BasicCleanup {
    /// Muletillas que nunca significan nada. «Este» u «o sea» no están: también son palabras normales.
    /// No se quitan unidades («5 mm», «2 em»), etiquetas («<em>») ni un «¿eh?» que es una pregunta.
    private static let fillerPattern = #"(?<![\p{L}\p{N}<¿])(?<!\d\s)(e+h+|e+h*m+|m{3,}|u+m+|u+h+m*|erm|h+m{2,})(?![\p{L}\p{N}>?])[,.]?[ \t]*"#

    public static func apply(_ text: String, style: WritingStyle) -> String {
        var result = text
        if let regex = try? NSRegularExpression(pattern: fillerPattern, options: [.caseInsensitive]) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }
        // Solo espacios y tabuladores: los saltos de línea («nuevo párrafo») se respetan.
        result = result
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+([,.;:!?])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = result.first else { return result }

        // Mayúscula inicial (después de «¿» o «¡» si los hay).
        if first == "¿" || first == "¡" {
            let rest = result.dropFirst()
            if let letter = rest.first {
                result = String(first) + letter.uppercased() + rest.dropFirst()
            }
        } else {
            result = first.uppercased() + result.dropFirst()
        }

        // Punto final si falta, salvo en un chat.
        if style != .casual, result.wordCount >= 3, let last = result.last, last.isLetter || last.isNumber {
            result += "."
        }
        return result
    }
}
