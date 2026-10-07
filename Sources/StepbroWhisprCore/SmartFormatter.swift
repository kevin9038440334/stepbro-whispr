import Foundation

/// Formato instantáneo, sin IA: comandos dictados, correos, signos ¿¡, preguntas evidentes,
/// listas y mayúsculas. Se aplica siempre, con o sin pulido, y tarda microsegundos.
public enum SmartFormatter {
    // MARK: - Antes del pulido

    /// Convierte lo que se dice "en voz alta" en formato: «nuevo párrafo», «arroba», «punto com»…
    public static func prepare(_ text: String) -> String {
        var result = text
        result = applySpokenCommands(result)
        result = joinEmailsAndLinks(result)
        result = removeStutters(result)
        return normalizeSpacing(result)
    }

    // MARK: - Después del pulido

    /// Retoques finales: listas, signos de apertura, preguntas evidentes, mayúsculas y espacios.
    public static func finish(_ text: String, language: String?) -> String {
        finish(text, languages: language.map { [$0] } ?? [])
    }

    /// Igual, para dictados que pueden mezclar idiomas: las reglas del español
    /// (¿¡, preguntas evidentes) se aplican solo a las frases en español.
    public static func finish(_ text: String, languages: [String]) -> String {
        var result = normalizeSpacing(text)
        result = formatOrdinalList(result)
        result = formatShoppingList(result)
        if languages.contains("es") {
            let spanishOnly = languages.count > 1
            // Aunque se dicte en español, una frase entera en inglés no lleva «¿» ni «¡».
            let isSpanish: (String) -> Bool = { sentence in
                if spanishOnly { return Languages.dominant(sentence, among: languages) == "es" }
                return sentence.wordCount < 4 || Languages.dominant(sentence, among: ["es", "en"]) == "es"
            }
            if spanishOnly { result = removeOpeningMarks(result, when: { !isSpanish($0) }) }
            result = markObviousExclamations(result, when: isSpanish)
            result = markObviousQuestions(result, when: isSpanish)
            result = addOpeningMarks(result, when: isSpanish)
        }
        result = capitalizeSentences(result)
        return normalizeSpacing(result)
    }

    /// ¿Hace falta un modelo de lenguaje? No, si el texto ya está limpio: así se pega al instante.
    public static func needsLanguageModel(_ text: String, alternative: String?) -> Bool {
        if matches(cuesPattern, text) || matches(restartPattern, text) || matches(dictatedPattern, text)
            || matches(negationPattern, text) { return true }
        // A partir de cierta longitud hay más que ganar (palabras mal oídas, frases sin cortar) que que perder.
        if text.wordCount >= 10 { return true }
        // Si las dos transcripciones no coinciden, el modelo elige la buena.
        if let alternative, agreement(text, alternative) < 0.85 { return true }
        return false
    }

    // MARK: - Comandos dictados

    private static let spokenCommands: [(pattern: String, replacement: String)] = [
        // Se respeta la puntuación de antes del comando («Hola Marta.») y se quita la de después.
        // Con un artículo delante («una nueva línea de código», «falta un punto y coma») no es una orden.
        (#"[ \t]*"# + notAfterDeterminer + #"\b(nuevo párrafo|punto y aparte|new paragraph)\b[,.;:]?[ \t]*"#, "\n\n"),
        (#"[ \t]*"# + notAfterDeterminer + #"\b(nueva línea|nueva linea|salto de línea|salto de linea|new line)\b(?!\s+de\b)[,.;:]?[ \t]*"#, "\n"),
        (#"\s*"# + notAfterDeterminer + #"\bpunto y coma\b\s*"#, "; "),
        (#"\s*(?<!\bno\s)\babre paréntesis\b\s*"#, " ("),
        (#"\s*\bcierra paréntesis\b\s*"#, ") "),
        (#"\s*\babre comillas\b\s*"#, " «"),
        (#"\s*\bcierra comillas\b\s*"#, "» "),
    ]

    private static let notAfterDeterminer = #"(?<!\b(?:una|un|la|el|esa|ese|otra|otro|cada|de|al|del|a|the)\s)"#

    static func applySpokenCommands(_ text: String) -> String {
        var result = text
        for command in spokenCommands {
            result = replace(command.pattern, in: result, with: command.replacement)
        }
        // Tras un salto de línea no debe quedar puntuación suelta (pero «.env» o «...» se respetan).
        result = replace(#"(?m)(?<=\n)[ \t]*[,.;:](?![\p{L}.])[ \t]*"#, in: result, with: "")
        return result
    }

    // MARK: - Correos y enlaces

    private static let domains = "com|es|net|org|mx|io|dev|co|info|edu|ai|app|me|ar|cl|pe|uy|eu|uk"
    /// Sin «arroba» delante, solo dominios que no se confunden con palabras («el punto es que…»).
    private static let linkDomains = "com|net|org|io|dev|ai|app"

    static func joinEmailsAndLinks(_ text: String) -> String {
        var result = text
        // «kevin arroba gmail punto com» → kevin@gmail.com
        result = replace(
            // Un punto escrito solo une si no lleva espacio detrás: «arroba Carlos. Es importante» no es un correo.
            #"(?i)\b(?!(?:con|un|una|el|la|de|a|en|por|y|decorador)\s+(?:arroba|@))([\p{L}\p{N}._-]+)\s+(?:arroba|@)\s+([\p{L}\p{N}-]+(?:(?:\s+punto\s+|\.(?=\S))[\p{L}\p{N}-]+)*?)(?:\s+punto\s+|\.(?=\S))("# + domains + #")\b"#,
            in: result
        ) { groups in
            let domain = groups[2].replacingOccurrences(of: #"\s+punto\s+|\."#, with: ".", options: [.regularExpression, .caseInsensitive])
            return (groups[1] + "@" + domain + "." + groups[3]).lowercased()
        }
        // «kevin @ gmail.com» → kevin@gmail.com
        result = replace(#"(?<!\b(?:con|un|una|el|la|de|decorador)\s)([\p{L}\p{N}._-]+)\s+@\s*([\p{L}\p{N}-]+\.("# + domains + #"))\b"#, in: result, with: "$1@$2")
        // «google punto com» → google.com
        result = replace(#"(?i)(?<!\b(?:este|ese|un|el|al|del|mi|tu|su)\s)\b(?!(?:este|ese|un|el|al|del|mi|tu|su)\s)([\p{L}\p{N}-]+)\s+punto\s+("# + linkDomains + #")\b"#, in: result) { groups in
            (groups[1] + "." + groups[2]).lowercased()
        }
        return result
    }

    // MARK: - Repeticiones

    /// «el el coche» → «el coche». Solo palabras cortas: «muy muy» o «no no» pueden ser intencionados.
    static func removeStutters(_ text: String) -> String {
        replace(
            #"(?i)\b(el|la|los|las|de|del|que|en|y|a|un|una|con|por|para|se|me|te|lo|le|the|an|to|of|and|in|is|I)(\s+)(\1)\b"#,
            in: text
        ) { groups in
            // «el El País»: la segunda es parte de un nombre, no una repetición.
            let repeated = groups[3].first?.isUppercase == true && groups[1].first?.isLowercase == true
            return repeated ? groups[0] : groups[1]
        }
    }

    // MARK: - Listas

    private static let ordinals = [
        ["primero", "en primer lugar", "first", "firstly"],
        ["segundo", "en segundo lugar", "second", "secondly"],
        ["tercero", "en tercer lugar", "third", "thirdly"],
        ["cuarto", "en cuarto lugar", "fourth"],
        ["quinto", "en quinto lugar", "fifth"],
        ["sexto", "sixth"],
        ["séptimo", "seventh"],
    ]

    /// «Tres cosas: primero, A; segundo, B; y tercero, C.» → lista numerada.
    /// «Uno, …, dos, …, y tres, …» o «1, …, 2, …, 3, …»: solo cuentan seguidos de coma, porque
    /// «uno» y los números son palabras corrientes.
    private static let cardinals = [
        ["uno", "1", "one"], ["dos", "2", "two"], ["tres", "3", "three"], ["cuatro", "4", "four"],
        ["cinco", "5", "five"], ["seis", "6", "six"], ["siete", "7", "seven"],
    ]

    static func formatOrdinalList(_ text: String) -> String {
        guard !isAlreadyList(text) else { return text }
        let positions = ordinalMarkers(in: text)
        if positions.count >= 3 || positions.count == 2 && positions.allSatisfy({ text[$0].hasSuffix(",") || text[$0].hasSuffix(":") }) {
            return buildList(text, markers: positions)
        }
        let numbered = cardinalMarkers(in: text)
        guard numbered.count >= 3 else { return text }
        return buildList(text, markers: numbered)
    }

    private static func cardinalMarkers(in text: String) -> [Range<String.Index>] {
        var positions: [Range<String.Index>] = []
        var searchStart = text.startIndex
        for words in cardinals {
            let pattern = #"(?i)(?<![\p{L}\p{N}.,])(?:y\s+|and\s+)?(?:"#
                + words.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + #")(?![\p{L}\p{N}]),"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(searchStart..., in: text)),
                  let range = Range(match.range, in: text)
            else { break }
            positions.append(range)
            searchStart = range.upperBound
        }
        return positions
    }

    private static func ordinalMarkers(in text: String) -> [Range<String.Index>] {
        var positions: [Range<String.Index>] = []
        var searchStart = text.startIndex
        let punctuated = text.contains(where: { ".,;:".contains($0) })
        for words in ordinals {
            // Solo cuenta el ordinal que abre una frase o un inciso («Primero, …», «. Segundo, …», «, y tercero …»):
            // «medio segundo», «por segundo» o «en segundo plano» no son marcas de lista.
            // En un texto sin puntuar (lo que da Apple sin IA) no hay frases que mirar: basta con que no lleve delante
            // una palabra que lo convierta en otra cosa.
            let opening = punctuated
                ? #"(?i)(?:^|[.;:\n,])\s*(?:y\s+|and\s+)?(?:"#
                : #"(?i)(?<![\p{L}])(?<!\b(?:un|el|la|lo|del|al|este|ese|cada|mi|tu|su|medio|por|en|a|de|otro)\s)(?:y\s+|and\s+)?(?:"#
            let pattern = opening
                + words.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
                + #")(?![\p{L}])(?!\s+(?:plano|lugar|piso|nombre|apellido|semestre|tiempo|que nada|of all))[,:]?"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(searchStart..., in: text)),
                  let range = Range(match.range, in: text)
            else { break }
            positions.append(range)
            searchStart = range.upperBound
        }
        return positions
    }

    /// Convierte el texto en lista a partir de las marcas («primero», «2,»…): lo de antes es la introducción.
    private static func buildList(_ text: String, markers positions: [Range<String.Index>]) -> String {
        let intro = String(text[..<positions[0].lowerBound])
        var items: [String] = []
        var remainder = ""
        for (offset, position) in positions.enumerated() {
            let isLast = offset + 1 == positions.count
            var raw = String(text[position.upperBound..<(isLast ? text.endIndex : positions[offset + 1].lowerBound)])
            // El último elemento acaba en su primera frase: lo que se diga después es texto normal.
            if isLast, let end = raw.range(of: #"[.?!](?=\s+\S)"#, options: .regularExpression) {
                remainder = raw[end.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                raw = String(raw[..<end.lowerBound])
            }
            items.append(cleanListItem(raw))
        }
        // Elementos de varios párrafos o frases no son una lista: es una explicación.
        guard items.allSatisfy({ !$0.isEmpty && !$0.contains("\n\n") && $0.wordCount <= 30 }) else { return text }

        var lines: [String] = []
        let cleanIntro = intro.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;.")))
        if !cleanIntro.isEmpty {
            lines.append(cleanIntro.hasSuffix(":") ? cleanIntro : cleanIntro + ":")
        }
        for (number, item) in items.enumerated() {
            lines.append("\(number + 1). \(item)")
        }
        return lines.joined(separator: "\n") + (remainder.isEmpty ? "" : "\n\n" + remainder)
    }

    /// «Lista de la compra: leche, huevos, pan y papel.» → lista con viñetas.
    /// Solo «lista de/para…»: «Lista los archivos, corre los tests…» es una orden, no una lista.
    static func formatShoppingList(_ text: String) -> String {
        guard !isAlreadyList(text),
              let match = firstMatch(#"(?i)^\s*((?:lista|list)\s+(?:de|del|para|of|for)\b[^:.,]{0,40})[:.,]\s*(.+?)\.?\s*$"#, in: text)
        else { return text }
        let intro = match[1].trimmingCharacters(in: .whitespaces)
        var body = match[2]
        var remainder = ""
        if let end = body.range(of: #"\.(?=\s+\S)"#, options: .regularExpression) {
            remainder = body[end.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            body = String(body[..<end.lowerBound])
        }
        // La «y» solo separa antes del último elemento («pan y leche, huevos» se queda junto).
        body = body.replacingOccurrences(of: #"\s+(?:y|e|and)\s+(?=[^,]+$)"#, with: ", ", options: .regularExpression)
        let items = body.replacingOccurrences(of: #",(?!\d)"#, with: "\u{1}", options: .regularExpression)
            .split(separator: "\u{1}").map { cleanListItem(String($0)) }.filter { !$0.isEmpty }
        guard items.count >= 3, items.allSatisfy({ $0.wordCount <= 4 }) else { return text }
        let list = ([intro.prefix(1).uppercased() + intro.dropFirst() + ":"] + items.map { "- \($0)" }).joined(separator: "\n")
        let closing = text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(".") ? "." : ""
        return list + (remainder.isEmpty ? "" : "\n\n" + remainder + closing)
    }

    private static func cleanListItem(_ item: String) -> String {
        var result = item.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;.:")))
        result = replace(#"(?i)\s+(?:y|and)$"#, in: result, with: "")
        guard let first = result.first else { return "" }
        return first.uppercased() + result.dropFirst()
    }

    private static func isAlreadyList(_ text: String) -> Bool {
        matches(#"(?m)^\s*(?:\d+[.)]|[-•*])\s+"#, text)
    }

    // MARK: - Preguntas y exclamaciones

    /// Palabras que solo pueden empezar una pregunta («qué» o «cómo» también abren exclamaciones).
    private static let questionStarts = [
        "dónde", "adónde", "cuándo", "cuál", "cuáles", "quién", "quiénes", "por qué", "para qué",
        "qué hora", "qué tal", "qué opinas", "qué piensas", "qué haces", "qué hay", "qué pasa",
        "qué te parece", "cómo estás", "cómo te", "cómo va", "cuántos", "cuántas",
    ]

    /// «Dónde has dejado las llaves.» → «¿Dónde has dejado las llaves?»
    static func markObviousQuestions(_ text: String, when applies: (String) -> Bool = { _ in true }) -> String {
        mapSentences(text) { sentence in
            let trimmed = sentence.trimmingCharacters(in: .whitespaces)
            // Con coma o dos puntos hay más de una idea («Por qué falla no lo sé, pero…»): eso lo decide la IA.
            guard !trimmed.hasSuffix("?"), !trimmed.hasSuffix("!"), !trimmed.contains(where: { ",:".contains($0) }),
                  applies(trimmed) else { return sentence }
            let body = trimmed.hasPrefix("¿") ? String(trimmed.dropFirst()) : trimmed
            let lower = body.lowercased()
            guard questionStarts.contains(where: { lower.hasPrefix($0 + " ") || lower == $0 }) else { return sentence }
            var core = body
            while let last = core.last, ".,;:".contains(last) { core.removeLast() }
            return "¿" + core + "?"
        }
    }

    /// Palabras tras «qué» que solo pueden ser exclamación: «qué bien», «qué pena»…
    private static let exclamationWords = [
        "bien", "bueno", "buena", "bonito", "bonita", "guay", "rico", "rica", "pena", "lástima", "suerte",
        "alegría", "ilusión", "horror", "asco", "fuerte", "maravilla", "genial", "susto", "rabia", "vergüenza",
        "frío", "calor", "hambre", "sueño", "pasada", "locura", "emoción", "gusto", "raro", "rara",
    ]

    /// «Que bien que vengas.» → «¡Qué bien que vengas!»
    static func markObviousExclamations(_ text: String, when applies: (String) -> Bool = { _ in true }) -> String {
        mapSentences(text) { sentence in
            let trimmed = sentence.trimmingCharacters(in: .whitespaces)
            // Solo exclamaciones cortas: «Que bien documentado esté el código me da igual» no lo es.
            guard !trimmed.hasSuffix("?"), !trimmed.hasSuffix("!"), !trimmed.contains(","), trimmed.wordCount <= 7,
                  applies(trimmed) else { return sentence }
            let body = trimmed.hasPrefix("¡") ? String(trimmed.dropFirst()) : trimmed
            let words = body.split(separator: " ", maxSplits: 2).map { $0.lowercased() }
            guard words.count >= 2, ["qué", "que"].contains(words[0]),
                  exclamationWords.contains(words[1].trimmingCharacters(in: .punctuationCharacters))
            else { return sentence }
            var core = "Qué" + body.dropFirst(3)
            while let last = core.last, ".,;:".contains(last) { core.removeLast() }
            return "¡" + core + "!"
        }
    }

    /// En español, las preguntas y exclamaciones se abren: «Oye, ¿vienes?», «¡Qué bien!».
    static func addOpeningMarks(_ text: String, when applies: (String) -> Bool = { _ in true }) -> String {
        mapSentences(text) { sentence in
            let trimmed = sentence.trimmingCharacters(in: .whitespaces)
            guard applies(trimmed) else { return sentence }
            // El signo de cierre tiene que cerrar una palabra: «??» o «a ? b» son código.
            let closesWord = trimmed.dropLast().last.map { $0.isLetter || $0.isNumber || ")»\"'".contains($0) } ?? false
            for (close, open) in [("?", "¿"), ("!", "¡")] where closesWord && trimmed.hasSuffix(close) && !trimmed.contains(open) {
                // Tras un vocativo o unas muletillas cortas («Oye, », «Marta, », «Ok, perfecto, »),
                // el signo va después de la última.
                var start = trimmed.startIndex
                var first = true
                while let comma = trimmed[start...].firstIndex(of: ","), trimmed.index(after: comma) < trimmed.endIndex {
                    let lead = trimmed[start..<comma].trimmingCharacters(in: .whitespaces)
                    let short = lead.split(separator: " ").count <= 2
                    guard short, first || leadIns.contains(lead.lowercased()) else { break }
                    start = trimmed.index(after: comma)
                    first = false
                }
                if start > trimmed.startIndex {
                    let rest = trimmed[start...].trimmingCharacters(in: .whitespaces)
                    return trimmed[..<start] + " " + open + lowercasedFirst(rest)
                }
                return open + trimmed
            }
            return sentence
        }
    }

    private static let leadIns: Set<String> = [
        "ok", "okay", "sí", "no", "claro", "perfecto", "bueno", "oye", "entonces", "vale", "ya", "pues", "mira", "bien",
    ]

    /// En un dictado que mezcla idiomas, las frases que no son en español no llevan «¿» ni «¡».
    static func removeOpeningMarks(_ text: String, when applies: (String) -> Bool) -> String {
        mapSentences(text) { sentence in
            let trimmed = sentence.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains(where: { "¿¡".contains($0) }) else { return sentence }
            let bare = trimmed.filter { !"¿¡".contains($0) }
            return applies(bare) ? bare : sentence
        }
    }

    private static func lowercasedFirst(_ text: String) -> String {
        guard let first = text.first, first.isUppercase else { return text }
        // Solo si la segunda letra es minúscula (no es una sigla ni un nombre en mayúsculas).
        let second = text.dropFirst().first
        return (second?.isLowercase ?? true) ? first.lowercased() + text.dropFirst() : text
    }

    // MARK: - Mayúsculas y espacios

    /// Mayúscula al empezar el texto, cada línea y cada frase (solo si tras el punto hay un espacio:
    /// así no se tocan correos ni enlaces como «gmail.com»).
    static func capitalizeSentences(_ text: String) -> String {
        let characters = Array(text)
        var result = ""
        result.reserveCapacity(text.count)
        var capitalizeNext = true
        var lineStart = 0
        for (index, character) in characters.enumerated() {
            if index > 0, ".?!".contains(characters[index - 1]), character.isWhitespace,
               closesWord(characters, before: index - 1), !endsWithAbbreviation(characters, before: index - 1) {
                capitalizeNext = true
            }
            if character == "\n" {
                result.append(character)
                capitalizeNext = true
                lineStart = index + 1
                continue
            }
            if capitalizeNext, character.isLetter {
                capitalizeNext = false
                // Tras una viñeta o un número de lista se respeta lo que venga: puede ser «npm install» o «main.swift».
                let lead = String(characters[lineStart..<index])
                let afterMarker = lead.range(of: #"^\s*(?:\d+[.)]|[-•*])\s+$"#, options: .regularExpression) != nil
                if afterMarker || isCodeLike(characters, at: index) {
                    result.append(character)
                } else {
                    result.append(contentsOf: character.uppercased())
                }
                continue
            }
            result.append(character)
            if character.isNumber {
                // «5 minutos y llego» no empieza con mayúscula tras el número; «1. Abrir» sí es un elemento de lista.
                let lead = String(characters[lineStart...index])
                if lead.range(of: #"^\s*\d+$"#, options: .regularExpression) == nil { capitalizeNext = false }
                else if index + 1 < characters.count, !characters[index + 1].isNumber, !".)".contains(characters[index + 1]) {
                    capitalizeNext = false
                }
            } else if !character.isWhitespace, !"¿¡-•*\"«(.?!)".contains(character) {
                capitalizeNext = false
            }
        }
        return result
    }

    private static let abbreviations: Set<String> = [
        "etc", "ej", "p", "aprox", "vs", "e.g", "i.e", "a.m", "p.m", "ee", "uu", "sr", "sra", "dr", "dra", "ud", "uds", "núm", "pág", "depto",
    ]

    /// Los signos que acaban en `index` cierran una palabra («hola.», «¿vienes?»), no van sueltos como en «a ?? b».
    private static func closesWord(_ characters: [Character], before index: Int) -> Bool {
        var start = index
        while start > 0, ".?!".contains(characters[start - 1]) { start -= 1 }
        guard start > 0 else { return false }
        let previous = characters[start - 1]
        return !previous.isWhitespace
    }

    /// El punto de `index` cierra una abreviatura («etc.», «p. ej.», «5 p.m.») o unos puntos suspensivos.
    private static func endsWithAbbreviation(_ characters: [Character], before index: Int) -> Bool {
        guard characters[index] == "." else { return false }
        if index >= 1, characters[index - 1] == "." { return true }
        var start = index
        while start > 0, !characters[start - 1].isWhitespace { start -= 1 }
        let word = String(characters[start..<index]).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "(«\"¿¡"))
        return abbreviations.contains(word) || (word.count == 1 && word.first?.isLetter == true && word != "y" && word != "a" && word != "o")
    }

    /// La palabra que empieza en `index` es un nombre de archivo, un enlace, un correo, una opción («--help»)
    /// o lleva mayúsculas propias («iPhone»): no se toca.
    private static func isCodeLike(_ characters: [Character], at index: Int) -> Bool {
        if index > 0, "-./_@~".contains(characters[index - 1]) { return true }
        var end = index
        while end < characters.count, !characters[end].isWhitespace { end += 1 }
        var word = String(characters[index..<end])
        while let last = word.last, ".,;:!?)»\"".contains(last) { word.removeLast() }
        return word.dropFirst().contains(where: { $0.isUppercase || $0.isNumber || "./@_:".contains($0) })
    }

    static func normalizeSpacing(_ text: String) -> String {
        var result = text
        result = replace(#"[ \t]{2,}"#, in: result, with: " ")
        // El espacio sobra solo si tras el signo acaba la palabra: «archivo .env» o «:)» se respetan.
        result = replace(#"[ \t]+([,.;:!?)»])(?=\s|$|[)»"'])"#, in: result, with: "$1")
        result = replace(#"([(«¿¡])[ \t]+"#, in: result, with: "$1")
        result = replace(#"(?<=\p{L})([,;])(?=\p{L})(?![^()\n]*\))"#, in: result, with: "$1 ")
        result = replace(#"[ \t]*\n[ \t]*"#, in: result, with: "\n")
        result = replace(#"\n{3,}"#, in: result, with: "\n\n")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - ¿Hace falta IA?

    /// Señales de que el texto necesita a alguien que entienda: autocorrecciones o muletillas ambiguas.
    private static let cuesPattern = #"(?i)(?<![\p{L}])(no,? perdón|perdón|digo|o mejor|mejor dicho|quiero decir|o sea|bueno,? no|no,? no|no,? mejor|espera|rectifico|corrijo|miento|me equivoqué|este,|pues nada|eh|em|mmm|i mean|sorry|actually|scratch that|wait|like,|you know|um|uh)(?![\p{L}])"#

    /// Algo dicho dos veces seguidas con la misma palabra delante («a las tres, a las cuatro»,
    /// «a Pedro, no, a Juan») o números dichos en voz alta: puede ser una rectificación.
    private static let restartPattern = #"(?i)(?<![\p{L}])(a|al|a las|a la|el|la|los|las|de|del|con|en|para|por|un|una|the|at|on|to)\s+[\p{L}\p{N}]+[,.]\s+(?:no,?\s+)?\1\s+[\p{L}\p{N}]+"#

    /// «Son cinco, no, seis», «El martes. No, el miércoles», «arriba, o no, abajo», «en rojo, mejor en azul».
    private static let negationPattern = #"(?i)[,.]\s*(?:o\s+)?no,\s|,\s*mejor\s|\sno\s+(?:el|la|los|las|a|al|en)\s"#

    /// Puntuación dicha en voz alta, ejemplos que van entre comillas o una palabra deletreada («C-L-A-U-D-E»).
    private static let dictatedPattern = #"(?i)(?<![\p{L}])(coma|punto|dos puntos|signo de \p{L}+|comillas|paréntesis|por ejemplo|for example|comma|period|question mark|quote)(?![\p{L}])|(?<![\p{L}])\p{L}[- ]\p{L}[- ]\p{L}(?![\p{L}])"#

    /// Proporción de palabras de `a` que también están en `b` (sin tildes, mayúsculas ni puntuación).
    public static func agreement(_ a: String, _ b: String) -> Double {
        let wordsA = Snippets.normalized(a).split(separator: " ")
        let wordsB = Set(Snippets.normalized(b).split(separator: " "))
        guard !wordsA.isEmpty else { return wordsB.isEmpty ? 1 : 0 }
        return Double(wordsA.filter(wordsB.contains).count) / Double(wordsA.count)
    }

    // MARK: - Utilidades

    /// Aplica una transformación a cada frase (separadas por . ? ! o saltos de línea), conservando los separadores.
    private static func mapSentences(_ text: String, _ transform: (String) -> String) -> String {
        // Un punto o un signo pegado a lo siguiente («main.swift», «2.0», «??») no acaba la frase.
        guard let regex = try? NSRegularExpression(pattern: #"(?:[^.?!\n]|[.?!](?=[^\s.?!]))+[.?!]*"#) else { return text }
        var result = ""
        var last = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            result += text[last..<range.lowerBound]
            let sentence = String(text[range])
            let leading = sentence.prefix { $0 == " " }
            result += leading + transform(String(sentence.dropFirst(leading.count)))
            last = range.upperBound
        }
        result += text[last...]
        return result
    }

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static func replace(_ pattern: String, in text: String, using transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            let groups = (0..<match.numberOfRanges).map { index -> String in
                guard let range = Range(match.range(at: index), in: text) else { return "" }
                return String(text[range])
            }
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: transform(groups))
            }
        }
        return result
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
