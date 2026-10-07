import Foundation
import Testing
@testable import StepbroWhisprCore

@Suite("Diccionario")
struct VocabularyTests {
    @Test func corrigeLoQueSeOyoMal() {
        let entries = [VocabularyEntry(term: "stepbro", heardAs: ["estep bro", "step bro"])]
        #expect(Vocabulary.apply(entries, to: "Abre estep bro terminal") == "Abre stepbro terminal")
        #expect(Vocabulary.apply(entries, to: "Step Bro es genial") == "stepbro es genial")
    }

    @Test func aceptaPalabrasPegadasOConGuion() {
        let entries = [VocabularyEntry(term: "Claude Code", heardAs: ["cloud code"])]
        #expect(Vocabulary.apply(entries, to: "Abre CloudCode y cloud-code") == "Abre Claude Code y Claude Code")
        #expect(Vocabulary.apply(entries, to: "subo el código a la cloud") == "subo el código a la cloud")
    }

    @Test func respetaMayusculasDelTermino() {
        let entries = [VocabularyEntry(term: "iPhone")]
        #expect(Vocabulary.apply(entries, to: "mi iphone y tu IPHONE") == "mi iPhone y tu iPhone")
    }

    @Test func soloPalabrasCompletas() {
        let entries = [VocabularyEntry(term: "Ana")]
        #expect(Vocabulary.apply(entries, to: "ana llamó a la banana") == "Ana llamó a la banana")
    }

    @Test func ignoraTildes() {
        let entries = [VocabularyEntry(term: "Begoña", heardAs: ["begona"])]
        #expect(Vocabulary.apply(entries, to: "Habla con begona y con Begóna") == "Habla con Begoña y con Begoña")
    }

    @Test func noRompeSimbolosEspeciales() {
        let entries = [VocabularyEntry(term: "C++", heardAs: ["c más más"])]
        #expect(Vocabulary.apply(entries, to: "programo en c más más") == "programo en C++")
    }
}

@Suite("Atajos de texto")
struct SnippetTests {
    let snippets = [
        Snippet(trigger: "mi correo", expansion: "kevin@ejemplo.com"),
        Snippet(trigger: "mi correo del trabajo", expansion: "kevin@empresa.com"),
    ]

    @Test func dictadoCompletoEsUnAtajo() {
        #expect(Snippets.wholeMatch(for: "Mi correo.", in: snippets)?.expansion == "kevin@ejemplo.com")
        #expect(Snippets.expand(snippets, in: "¡Mi correo!") == "kevin@ejemplo.com")
    }

    @Test func atajoDentroDeUnaFrase() {
        #expect(Snippets.expand(snippets, in: "Te paso mi correo por aquí") == "Te paso kevin@ejemplo.com por aquí")
    }

    @Test func ganaElAtajoMasLargo() {
        #expect(Snippets.expand(snippets, in: "Escribe a mi correo del trabajo") == "Escribe a kevin@empresa.com")
    }

    @Test func sinAtajosNoCambiaNada() {
        #expect(Snippets.expand([], in: "Hola, ¿qué tal?") == "Hola, ¿qué tal?")
    }
}

@Suite("Estilos")
struct StyleTests {
    @Test func categoriasPorApp() {
        #expect(AppCategory(bundleID: "net.whatsapp.WhatsApp") == .messages)
        #expect(AppCategory(bundleID: "com.apple.mail") == .email)
        #expect(AppCategory(bundleID: "com.microsoft.VSCode") == .code)
        #expect(AppCategory(bundleID: "com.jetbrains.intellij") == .code)
        #expect(AppCategory(bundleID: "com.apple.Notes") == .other)
        #expect(AppCategory(bundleID: nil) == .other)
    }

    @Test func casualQuitaElPuntoDeUnaFraseCorta() {
        #expect(StyleFormatter.finish("Voy para allá.", style: .casual) == "Voy para allá")
        #expect(StyleFormatter.finish("Voy para allá. Llego en diez.", style: .casual) == "Voy para allá. Llego en diez.")
        #expect(StyleFormatter.finish("Espera...", style: .casual) == "Espera...")
        #expect(StyleFormatter.finish("Voy para allá.", style: .formal) == "Voy para allá.")
    }
}

@Suite("Redes de seguridad del pulido")
struct PolishGuardTests {
    @Test func limpiaComillasYEtiquetas() {
        #expect(PolishGuard.sanitize("«Hola, Marta.»") == "Hola, Marta.")
        #expect(PolishGuard.sanitize("<transcript>\nHola\n</transcript>") == "Hola")
    }

    @Test func rechazaRespuestasInventadas() {
        let raw = "qué hora es en Tokio"
        #expect(PolishGuard.isPlausibleLocal("¿Qué hora es en Tokio?", for: raw))
        #expect(!PolishGuard.isPlausibleLocal(String(repeating: "En Tokio son las cinco de la tarde. ", count: 3), for: raw))
        #expect(!PolishGuard.isPlausibleCloud("", for: raw))
    }

    @Test func detectaTraducciones() {
        let spanish = Locale(identifier: "es_ES")
        #expect(PolishGuard.isWritten(in: spanish, "¿Qué hora es en Tokio ahora mismo?"))
        #expect(!PolishGuard.isWritten(in: spanish, "What time is it in Tokyo right now?"))
    }

    @Test func detectaPalabrasAnadidasAlFinal() {
        let raw = "eh oye ya voy para allá"
        #expect(PolishGuard.isPlausibleLocal("Oye, ya voy para allá", for: raw))
        #expect(!PolishGuard.isPlausibleLocal("Oye ya voy para allá mi correo", for: raw))
        let longRaw = "estoy usando estep bro whisper en mi iphone y la verdad funciona genial"
        #expect(!PolishGuard.isPlausibleLocal("Estoy usando stepbro whisper en mi iPhone y la verdad funciona genial. Mi correo.", for: longRaw))
        #expect(PolishGuard.addedWords(in: "¿Qué hora es?", comparedTo: "que hora es") == 0)
    }

    @Test func elModeloLocalNoRecibeLasListas() {
        let input = PolishInput(
            transcript: "hola",
            locale: Locale(identifier: "es_ES"),
            vocabulary: ["stepbro"],
            protectedPhrases: ["mi correo"]
        )
        let context = PolishPrompt.context(for: input, includeLists: false)
        #expect(!context.contains("stepbro"))
        #expect(!context.contains("mi correo"))
    }

    @Test func contextoIncluyeDiccionarioYAtajos() {
        let input = PolishInput(
            transcript: "hola",
            locale: Locale(identifier: "es_ES"),
            style: .casual,
            appName: "WhatsApp",
            vocabulary: ["stepbro"],
            protectedPhrases: ["mi correo"]
        )
        let context = PolishPrompt.context(for: input)
        #expect(context.contains("Language: Spanish"))
        #expect(context.contains("App: WhatsApp"))
        #expect(context.contains("stepbro"))
        #expect(context.contains("\"mi correo\""))
    }
}

@Suite("Estadísticas")
struct StatsTests {
    @Test func rachaDeDias() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let day: (Int) -> Date = { calendar.date(byAdding: .day, value: -$0, to: now)! }
        let history = [0, 1, 2, 4].map { Dictation(text: "hola", date: day($0)) }
        #expect(DictationStats.streak(in: history, now: now, calendar: calendar) == 3)
        #expect(DictationStats.streak(in: [], now: now, calendar: calendar) == 0)
    }

    @Test func palabrasPorMinutoYAhorro() {
        var stats = DictationStats()
        stats.add(Dictation(text: Array(repeating: "palabra", count: 150).joined(separator: " "), date: .now, duration: 60))
        #expect(stats.wordsPerMinute == 150)
        // 150 palabras tecleadas a 40/min son 3,75 min; dictadas, 1 min.
        #expect(stats.minutesSaved == 3)
    }
}

@Suite("Limpieza básica")
struct BasicCleanupTests {
    @Test func quitaMuletillasInequivocas() {
        #expect(BasicCleanup.apply("eh hola marta, mmm te escribo por lo del jueves", style: .normal) == "Hola marta, te escribo por lo del jueves.")
        #expect(BasicCleanup.apply("um so I was thinking", style: .normal) == "So I was thinking.")
    }

    @Test func respetaPalabrasQueParecenMuletillas() {
        // «este» y «o sea» pueden tener significado: no se tocan.
        #expect(BasicCleanup.apply("este coche es mío", style: .normal) == "Este coche es mío.")
        #expect(BasicCleanup.apply("hemos visto el humo", style: .normal) == "Hemos visto el humo.")
    }

    @Test func mayusculaYPuntoSegunEstilo() {
        #expect(BasicCleanup.apply("¿vienes mañana?", style: .normal) == "¿Vienes mañana?")
        #expect(BasicCleanup.apply("ya voy para allá", style: .casual) == "Ya voy para allá")
        #expect(BasicCleanup.apply("vale", style: .formal) == "Vale")
    }
}
