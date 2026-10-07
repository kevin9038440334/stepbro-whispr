import Foundation
import Testing
@testable import StepbroWhisprCore

/// Casos que una auditoría encontró rotos: frases corrientes que las reglas estropeaban.
@Suite("Auditoría de reglas")
struct AuditTests {
    private func finish(_ text: String, _ languages: [String] = ["es"]) -> String {
        SmartFormatter.finish(text, languages: languages)
    }

    @Test func losPuntosDentroDeUnaPalabraNoPartenLaFrase() {
        #expect(finish("¿Puedes revisar el archivo main.swift y decirme qué hace la función en la v2.1?")
            == "¿Puedes revisar el archivo main.swift y decirme qué hace la función en la v2.1?")
        #expect(finish("Dónde está el archivo main.swift?") == "¿Dónde está el archivo main.swift?")
        #expect(finish("¿Qué opinas de la versión 2.0 de Next.js?") == "¿Qué opinas de la versión 2.0 de Next.js?")
        #expect(finish("Viste lo de google.com/maps?") == "¿Viste lo de google.com/maps?")
        #expect(finish("Usa el operador ?? para el valor por defecto.") == "Usa el operador ?? para el valor por defecto.")
    }

    @Test func elInglesNoLlevaSignosDeApertura() {
        #expect(finish("Can you fix the login bug?") == "Can you fix the login bug?")
        #expect(finish("Revisa el código. Does it work now?") == "Revisa el código. Does it work now?")
    }

    @Test func elSignoVaTrasLasMuletillas() {
        #expect(finish("Ok, perfecto, entonces lo subes hoy?") == "Ok, perfecto, ¿entonces lo subes hoy?")
        #expect(finish("Sí, claro, vienes mañana?") == "Sí, claro, ¿vienes mañana?")
        #expect(finish("Oye, vienes mañana?") == "Oye, ¿vienes mañana?")
    }

    @Test func preguntasYExclamacionesSoloSiSonEvidentes() {
        #expect(finish("Cómo se instala:\n1. Descarga el zip\n2. Ábrelo") == "Cómo se instala:\n1. Descarga el zip\n2. Ábrelo")
        #expect(finish("Por qué no funciona no lo sé, pero hay que arreglarlo.") == "Por qué no funciona no lo sé, pero hay que arreglarlo.")
        #expect(finish("Que bien documentado esté el código me da igual.") == "Que bien documentado esté el código me da igual.")
        #expect(finish("Dónde has dejado las llaves.") == "¿Dónde has dejado las llaves?")
    }

    @Test func lasMayusculasRespetanNumerosYCodigo() {
        #expect(finish("5 minutos y llego") == "5 minutos y llego")
        #expect(finish("main.swift tiene un bug") == "main.swift tiene un bug")
        #expect(finish("--help muestra la ayuda") == "--help muestra la ayuda")
        #expect(finish("iPhone 15 es muy caro") == "iPhone 15 es muy caro")
        #expect(finish("Comandos:\n- npm install\n- git push") == "Comandos:\n- npm install\n- git push")
        #expect(finish("Bueno... no sé qué decirte.") == "Bueno... no sé qué decirte.")
        #expect(finish("Mira, etc. y luego seguimos.") == "Mira, etc. y luego seguimos.")
        #expect(finish("hola. ya llegué a casa.") == "Hola. Ya llegué a casa.")
        #expect(finish("Pasos:\n1. abrir\n2. cerrar") == "Pasos:\n1. abrir\n2. cerrar")
    }

    @Test func losEspaciosRespetanArchivosOcultos() {
        #expect(SmartFormatter.prepare("abre el archivo .env y el .gitignore") == "abre el archivo .env y el .gitignore")
        #expect(SmartFormatter.prepare("hola , qué tal") == "hola, qué tal")
    }

    @Test func lasOrdenesDictadasNoSaltanEnFrasesNormales() {
        #expect(SmartFormatter.prepare("agrega una nueva línea de código al final del archivo") == "agrega una nueva línea de código al final del archivo")
        #expect(SmartFormatter.prepare("falta un punto y coma al final de la línea 20") == "falta un punto y coma al final de la línea 20")
        #expect(SmartFormatter.prepare("Hola Marta. Nuevo párrafo. Te escribo por lo del jueves.") == "Hola Marta.\n\nTe escribo por lo del jueves.")
    }

    @Test func noSeInventanCorreosNiEnlaces() {
        #expect(SmartFormatter.prepare("menciona a Carlos con arroba Carlos. Es importante que lo vea")
            == "menciona a Carlos con arroba Carlos. Es importante que lo vea")
        #expect(SmartFormatter.prepare("en este punto app ya no responde") == "en este punto app ya no responde")
        #expect(SmartFormatter.prepare("mi correo es kevin arroba gmail punto com") == "mi correo es kevin@gmail.com")
    }

    @Test func elDiccionarioNoTocaRutasNiIdentificadores() {
        let entries = [
            VocabularyEntry(term: "Claude Code", heardAs: ["cloud code"]),
            VocabularyEntry(term: "Claude", heardAs: ["claud"]),
            VocabularyEntry(term: "Groq", heardAs: ["groc"]),
            VocabularyEntry(term: "Anthropic"),
            VocabularyEntry(term: "ChatGPT", heardAs: ["chat gpt"]),
        ]
        for text in [
            "abre ~/.claude/settings.json", "edita el archivo CLAUDE.md", "usa el paquete claude-code",
            "escribe a soporte@anthropic.com", "entra a claude.ai y a console.groq.com", "la variable groq_api_key",
            "Opciones:\n- Chat\n- GPT",
        ] {
            #expect(Vocabulary.apply(entries, to: text) == text)
        }
        #expect(Vocabulary.apply(entries, to: "le pregunté a claude y a chat gpt") == "le pregunté a Claude y a ChatGPT")
    }

    @Test func lasVariantesCortasNoSePegan() {
        let entries = [VocabularyEntry(term: "Entorno", heardAs: ["en torno"])]
        #expect(Vocabulary.apply(entries, to: "gira entornos") == "gira entornos")
        let snippets = [Snippet(trigger: "firma", expansion: "Saludos, Kevin")]
        #expect(Snippets.expand(snippets, in: "confirma la firma") == "confirma la Saludos, Kevin")
    }

    @Test func segundoComoUnidadNoEsUnaLista() {
        let time = "Primero, déjame explicarte el problema. La app tarda como medio segundo, y eso es mucho."
        #expect(finish(time) == time)
        let plane = "Primero quiero que revises el código, corre en segundo plano, y en tercero no sé."
        #expect(finish(plane) == plane)
        #expect(finish("Primero, revisa el login. Segundo, sube el build. Después de eso quiero que me avises.")
            == "1. Revisa el login\n2. Sube el build\n\nDespués de eso quiero que me avises.")
    }

    @Test func listasConNumeros() {
        #expect(finish("Para el viaje necesito, 1, el pasaporte, 2, los boletos, y 3, el cargador.")
            == "Para el viaje necesito:\n1. El pasaporte\n2. Los boletos\n3. El cargador")
        #expect(finish("Para el viaje necesito uno, el pasaporte, dos, los boletos y tres, el cargador.")
            == "Para el viaje necesito:\n1. El pasaporte\n2. Los boletos\n3. El cargador")
        // Números corrientes no son una lista.
        let plain = "Compré 1 kilo de pan, 2 de arroz y 3 litros de leche."
        #expect(finish(plain) == plain)
        let words = "Uno de ellos llegó tarde, dos se fueron y tres no vinieron."
        #expect(finish(words) == words)
    }

    @Test func listaSoloSiEsUnaLista() {
        let order = "Lista los archivos de la carpeta, corre los tests, haz el commit y avísame."
        #expect(finish(order) == order)
        #expect(finish("Lista de la compra: leche, huevos y pan. Luego te llamo.")
            == "Lista de la compra:\n- Leche\n- Huevos\n- Pan\n\nLuego te llamo.")
    }

    @Test func laLimpiezaBasicaNoBorraUnidades() {
        #expect(BasicCleanup.apply("pon un tornillo de 5 mm", style: .normal) == "Pon un tornillo de 5 mm.")
        #expect(BasicCleanup.apply("eh, bueno, eh, vamos", style: .casual) == "Bueno, vamos")
    }

    @Test func lasRectificacionesCortasPasanPorLaIA() {
        for text in ["Son cinco, no, seis.", "El martes. No, el miércoles.", "Ponlo en rojo, mejor en azul.", "Pon el botón arriba, o no, abajo."] {
            #expect(SmartFormatter.needsLanguageModel(text, alternative: nil))
        }
    }

    @Test func lasRedesNoRechazanLoBueno() {
        let cancel = "Quiero que vayas a la tienda y compres leche, huevos, pan, no, espera, olvida todo eso, mejor solo dime qué hora es."
        #expect(PolishGuard.isPlausibleCloud("Mejor solo dime qué hora es.", for: cancel))
        #expect(PolishGuard.isFaithful("Mejor solo dime qué hora es.", to: [cancel]))
        #expect(PolishGuard.isFaithful(
            "Haz un commit y un push a la rama main y abre un pull request.",
            to: ["has un comit y un push a la rama mein y abre un pul ricuest"]
        ))
        #expect(PolishGuard.sanitize("\"Hola\" le dije, y me contestó \"adiós\"") == "\"Hola\" le dije, y me contestó \"adiós\"")
        #expect(PolishGuard.sanitize("\"Hola, Marta.\"") == "Hola, Marta.")
        #expect(PolishGuard.removingEcho(of: "Hay que probar", from: "Hay que probarlo bien antes de subir.") == "Hay que probarlo bien antes de subir.")
        let english = PolishInput(transcript: "git push origin main", locale: Locale(identifier: "es_ES"))
        #expect(PolishGuard.hasExpectedLanguage("git push origin main", for: english))
    }

    @Test func lasRedesRechazanUnaRespuestaCorta() {
        #expect(!PolishGuard.isFaithful("Cuatro.", to: ["¿Cuánto es dos más dos?"]))
        #expect(!PolishGuard.isFaithful("Claro, lo reviso.", to: ["eh puedes revisar el login"]))
        #expect(!PolishGuard.isFaithful("Sí, claro.", to: ["puedes ayudarme con esto"]))
    }

    @Test func unGraciasDeVerdadSeQueda() {
        #expect(TranscriptChooser.choose(whisper: "Te lo mando mañana. Muchas gracias.", local: "te lo mando mañana mucha gracia")
            == "Te lo mando mañana. Muchas gracias.")
        #expect(TranscriptChooser.choose(whisper: "Muchas gracias.", local: "muchas gracia") == "Muchas gracias.")
        #expect(!TranscriptChooser.wasOnlyNoise(local: "Sí", seconds: 7))
    }

    @Test func continuarNoBajaLosNombres() {
        #expect(ContextJoiner.adapt("María y me dijo que sí.", after: "Ayer hablé con") == " María y me dijo que sí.")
        #expect(ContextJoiner.adapt("Xcode para compilar.", after: "usa") == " Xcode para compilar.")
        #expect(ContextJoiner.adapt("1. Revisar\n2. Subir", after: "Tareas:") == "\n1. Revisar\n2. Subir")
    }

    @Test func unaListaYLuegoTexto() {
        #expect(LongDictation.joinPolished(["Hay dos cosas:\n1. Revisar\n2. Subirlo", "Después revisa el login."])
            == "Hay dos cosas:\n1. Revisar\n2. Subirlo\n\nDespués revisa el login.")
        #expect(LongDictation.joinPolished(["El total fue de", "3. 5 personas no pagaron."]) == "El total fue de 3. 5 personas no pagaron.")
    }

    @Test func claudeYCloud() {
        let entries = [VocabularyEntry(term: "Claude", heardAs: ["claud"], confusedWith: ["cloud"])]
        #expect(Vocabulary.hasAmbiguousWord("lo subo a la Claude", in: entries))
        #expect(Vocabulary.hasAmbiguousWord("lo subo a la cloud", in: entries))
        #expect(!Vocabulary.hasAmbiguousWord("lo subo a la nube", in: entries))
        // «cloud» a secas nunca se sustituye: solo la IA decide por el contexto.
        #expect(Vocabulary.apply(entries, to: "Google Cloud y la cloud") == "Google Cloud y la cloud")
        // Un diccionario guardado antes de existir el campo se sigue leyendo.
        let old = Data(#"{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","term":"Claude","heardAs":["claud"]}"#.utf8)
        #expect((try? JSONDecoder().decode(VocabularyEntry.self, from: old))?.confusedWith == [])
    }
}
