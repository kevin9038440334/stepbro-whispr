import Foundation
import Testing
@testable import StepbroWhisprCore

@Suite("Formato instantáneo")
struct SmartFormatterTests {
    // MARK: Comandos dictados

    @Test func parrafosYLineas() {
        #expect(SmartFormatter.prepare("Hola Marta. Nuevo párrafo. Te escribo para confirmar.")
            == "Hola Marta.\n\nTe escribo para confirmar.")
        #expect(SmartFormatter.prepare("lista nueva línea leche") == "lista\nleche")
        #expect(SmartFormatter.prepare("Gracias, punto y aparte, un saludo") == "Gracias,\n\nun saludo")
    }

    @Test func parentesisYPuntoYComa() {
        #expect(SmartFormatter.prepare("el lunes abre paréntesis festivo cierra paréntesis no hay clase")
            == "el lunes (festivo) no hay clase")
        #expect(SmartFormatter.prepare("vale punto y coma nos vemos") == "vale; nos vemos")
    }

    // MARK: Correos y enlaces

    @Test func correosDictados() {
        #expect(SmartFormatter.prepare("Mi correo es kevin arroba gmail punto com.") == "Mi correo es kevin@gmail.com.")
        #expect(SmartFormatter.prepare("escribe a ana.lopez arroba empresa punto es") == "escribe a ana.lopez@empresa.es")
        #expect(SmartFormatter.prepare("kevin @ gmail.com") == "kevin@gmail.com")
    }

    @Test func enlacesSinConfundirFrases() {
        #expect(SmartFormatter.prepare("entra en google punto com") == "entra en google.com")
        #expect(SmartFormatter.prepare("el punto es que no llego") == "el punto es que no llego")
    }

    @Test func repeticiones() {
        #expect(SmartFormatter.prepare("vamos a a la casa de de Ana") == "vamos a la casa de Ana")
        #expect(SmartFormatter.prepare("muy muy bien") == "muy muy bien")
    }

    // MARK: Listas

    @Test func listaConOrdinales() {
        let text = "Tengo que hacer tres cosas. Primero, llamar al banco. Segundo, pagar la luz. Y tercero, comprar el regalo de Ana."
        #expect(SmartFormatter.finish(text, language: "es")
            == "Tengo que hacer tres cosas:\n1. Llamar al banco\n2. Pagar la luz\n3. Comprar el regalo de Ana")
    }

    @Test func listaSinComasConTresOrdinales() {
        let text = "tengo que hacer tres cosas primero llamar al banco segundo pagar la luz y tercero comprar pan"
        #expect(SmartFormatter.finish(text, language: "es")
            == "Tengo que hacer tres cosas:\n1. Llamar al banco\n2. Pagar la luz\n3. Comprar pan")
    }

    @Test func noEsListaSiNoLoParece() {
        #expect(SmartFormatter.finish("Primero voy yo y en un segundo vas tú.", language: "es") == "Primero voy yo y en un segundo vas tú.")
        #expect(SmartFormatter.finish("Espera un segundo.", language: "es") == "Espera un segundo.")
    }

    @Test func listaDeLaCompra() {
        #expect(SmartFormatter.finish("Lista de la compra: leche, huevos, pan y papel de cocina.", language: "es")
            == "Lista de la compra:\n- Leche\n- Huevos\n- Pan\n- Papel de cocina")
    }

    @Test func noTocaListasYaHechas() {
        let list = "Tareas:\n1. Uno\n2. Dos"
        #expect(SmartFormatter.finish(list, language: "es") == list)
    }

    // MARK: Preguntas y exclamaciones

    @Test func signosDeApertura() {
        #expect(SmartFormatter.finish("Me puedes pasar el informe cuando puedas?", language: "es")
            == "¿Me puedes pasar el informe cuando puedas?")
        #expect(SmartFormatter.finish("Oye, me puedes pasar el informe?", language: "es")
            == "Oye, ¿me puedes pasar el informe?")
        #expect(SmartFormatter.finish("Qué bien que vengas!", language: "es") == "¡Qué bien que vengas!")
        #expect(SmartFormatter.finish("Hola. Vienes mañana?", language: "es") == "Hola. ¿Vienes mañana?")
    }

    @Test func preguntasEvidentesSinSigno() {
        #expect(SmartFormatter.finish("Qué hora es en Tokio ahora mismo", language: "es") == "¿Qué hora es en Tokio ahora mismo?")
        #expect(SmartFormatter.finish("Dónde has dejado las llaves.", language: "es") == "¿Dónde has dejado las llaves?")
        // «Qué» abre también exclamaciones: «qué bien» es exclamación, «qué haces» pregunta.
        #expect(SmartFormatter.finish("Qué bien que vengas.", language: "es") == "¡Qué bien que vengas!")
        #expect(SmartFormatter.finish("Qué haces esta noche.", language: "es") == "¿Qué haces esta noche?")
        // Sin pistas claras no se toca.
        #expect(SmartFormatter.finish("Qué casa tan grande.", language: "es") == "Qué casa tan grande.")
    }

    @Test func exclamacionesEvidentes() {
        #expect(SmartFormatter.finish("Que bien que vengas a la cena.", language: "es") == "¡Qué bien que vengas a la cena!")
        #expect(SmartFormatter.finish("Qué pena", language: "es") == "¡Qué pena!")
    }

    @Test func parrafosSobrevivenALaLimpieza() {
        let text = SmartFormatter.prepare("Hola Marta. Nuevo párrafo. Te escribo para confirmar.")
        #expect(BasicCleanup.apply(text, style: .normal) == "Hola Marta.\n\nTe escribo para confirmar.")
    }

    @Test func enInglesNoHaySignosDeApertura() {
        #expect(SmartFormatter.finish("can you send it?", language: "en") == "Can you send it?")
    }

    // MARK: Mayúsculas y espacios

    @Test func mayusculasSinRomperCorreos() {
        #expect(SmartFormatter.finish("escríbeme a kevin@gmail.com. gracias", language: "es")
            == "Escríbeme a kevin@gmail.com. Gracias")
        #expect(SmartFormatter.finish("cuesta 3.5 euros", language: "es") == "Cuesta 3.5 euros")
    }

    @Test func espacios() {
        #expect(SmartFormatter.normalizeSpacing("hola ,  qué tal ?") == "hola, qué tal?")
        #expect(SmartFormatter.normalizeSpacing("uno,dos") == "uno, dos")
        #expect(SmartFormatter.normalizeSpacing("a las 10:30, vale") == "a las 10:30, vale")
    }

    // MARK: ¿Hace falta IA?

    @Test func iaSoloCuandoHaceFalta() {
        #expect(!SmartFormatter.needsLanguageModel("Vale, perfecto.", alternative: "Vale, perfecto."))
        #expect(SmartFormatter.needsLanguageModel("Quedamos a las cinco, no, perdón, a las seis.", alternative: nil))
        #expect(SmartFormatter.needsLanguageModel("¿Qué hora es el occhio ahora mismo?", alternative: "¿Qué hora es en Tokio ahora mismo?"))
        #expect(!SmartFormatter.needsLanguageModel("¿Vienes mañana?", alternative: "Vienes mañana"))
    }
}

@Suite("Idiomas")
struct LanguageTests {
    @Test func mezclaDeIdiomasSoloAbreLasFrasesEnEspanol() {
        let text = "Oye, vienes mañana a la reunión? Can you send me the report before Friday? Qué bien!"
        #expect(SmartFormatter.finish(text, languages: ["es", "en"])
            == "Oye, ¿vienes mañana a la reunión? Can you send me the report before Friday? ¡Qué bien!")
    }

    @Test func contextoParaTraducirOMezclar() {
        let spanish = Locale(identifier: "es_ES")
        let translate = PolishPrompt.context(for: PolishInput(transcript: "hola", locale: spanish, translateTo: "en"))
        #expect(translate.contains("translate the final text into English"))
        let mixed = PolishPrompt.context(for: PolishInput(transcript: "hola", locale: spanish, mixedLanguages: true))
        #expect(mixed.contains("switch between languages"))
        let normal = PolishPrompt.context(for: PolishInput(transcript: "hola", locale: spanish))
        #expect(normal.contains("Language: Spanish"))
    }

    @Test func idiomaEsperadoDelResultado() {
        let spanish = Locale(identifier: "es_ES")
        let raw = "tengo que revisar el informe antes de la reunión de mañana"
        // Traducir: el resultado debe estar en el idioma de destino.
        let toEnglish = PolishInput(transcript: raw, locale: spanish, translateTo: "en")
        #expect(PolishGuard.hasExpectedLanguage("I have to review the report before tomorrow's meeting.", for: toEnglish))
        #expect(!PolishGuard.hasExpectedLanguage("Tengo que revisar el informe antes de la reunión de mañana.", for: toEnglish))
        // Sin traducir: si el modelo traduce por su cuenta, se descarta.
        let keep = PolishInput(transcript: raw, locale: spanish)
        #expect(!PolishGuard.hasExpectedLanguage("I have to review the report before tomorrow's meeting.", for: keep))
        // Mezcla: vale lo que se dijo; no vale traducirlo todo.
        let mixed = PolishInput(transcript: raw, locale: spanish, mixedLanguages: true)
        #expect(PolishGuard.hasExpectedLanguage("Tengo que revisar el informe antes de la reunión de mañana.", for: mixed))
        #expect(!PolishGuard.hasExpectedLanguage("I have to review the report before tomorrow's meeting.", for: mixed))
    }

    @Test func destinosDeTraduccion() {
        #expect(TranslationTarget.none.code == nil)
        #expect(TranslationTarget.english.code == "en")
        #expect(Languages.englishName("es") == "Spanish")
    }

    @Test func whisperTraduceYMandaApple() {
        let whisper = "Mañana tengo la reunión con el cliente. ¿Puedes enviarme el reporte antes del viernes?"
        let apple = "Mañana tengo la reunión con el cliente. Can you send me the report before Friday?"
        let choice = TranscriptChooser.preferOriginalLanguages(primary: whisper, alternative: apple, among: ["es", "en"])
        #expect(choice.swapped)
        #expect(choice.primary == apple)
        #expect(choice.alternative == whisper)
        // Con un solo idioma no se cambia nada.
        let single = TranscriptChooser.preferOriginalLanguages(primary: whisper, alternative: apple, among: ["es"])
        #expect(!single.swapped)
    }

    @Test func etiquetasDeLasTranscripciones() {
        var input = PolishInput(transcript: "uno", alternative: "dos", locale: Locale(identifier: "es_ES"), mixedLanguages: true)
        input.transcriptSource = "apple"
        input.alternativeSource = "whisper"
        let message = PolishPrompt.smartMessage(for: input)
        #expect(message.contains("apple: uno\nwhisper: dos"))
    }

    @Test func laMezclaNoPuedePerderUnIdioma() {
        let dictated = "Mañana tengo la reunión con el cliente. Can you send me the report before Friday?"
        let input = PolishInput(transcript: dictated, locale: Locale(identifier: "es_ES"), mixedLanguages: true)
        #expect(PolishGuard.hasExpectedLanguage(dictated, for: input))
        #expect(!PolishGuard.hasExpectedLanguage("Mañana tengo la reunión con el cliente. ¿Puedes enviarme el informe antes del viernes?", for: input))
    }

    @Test func enMezclasElInglesNoLlevaSignoDeApertura() {
        let text = "Mañana tengo la reunión con el cliente. ¿Can you send me the report before Friday?"
        #expect(SmartFormatter.finish(text, languages: ["es", "en"])
            == "Mañana tengo la reunión con el cliente. Can you send me the report before Friday?")
        #expect(SmartFormatter.finish("Oye, ¿vienes mañana a la fiesta?", languages: ["es", "en"]) == "Oye, ¿vienes mañana a la fiesta?")
    }
}
