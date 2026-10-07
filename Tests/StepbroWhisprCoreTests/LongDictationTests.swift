import Foundation
import Testing
@testable import StepbroWhisprCore

@Suite("Cortes en las pausas")
struct PauseDetectorTests {
    /// Alimenta el detector con tramos (nivel, segundos) y devuelve en qué segundos corta.
    private func cuts(_ stretches: [(level: Float, seconds: Double)]) -> [Double] {
        var detector = PauseDetector()
        var time = 0.0
        var result: [Double] = []
        for stretch in stretches {
            var remaining = stretch.seconds
            while remaining > 0 {
                time += 0.035
                remaining -= 0.035
                if detector.feed(level: stretch.level, elapsed: 0.035) { result.append(time) }
            }
        }
        return result
    }

    @Test func unDictadoCortoNoSeCorta() {
        #expect(cuts([(0.6, 4), (0.02, 1), (0.6, 4)]).isEmpty)
    }

    @Test func cortaEnLaPrimeraPausaPasadoElMinimo() {
        let result = cuts([(0.6, 6), (0.02, 1), (0.6, 6), (0.02, 1), (0.6, 5)])
        #expect(result.count == 1)
        #expect(result[0] > 13.3 && result[0] < 13.7)
    }

    @Test func sinPausasCortaAlLlegarAlMaximo() {
        let result = cuts([(0.6, 30)])
        #expect(result.count == 1)
        #expect(result[0] > 27.9 && result[0] < 28.2)
    }

    @Test func elSilencioNoSeCorta() {
        // Tras hablar y cortar, quedarse callado no genera trozos vacíos (Whisper se los inventaría).
        let result = cuts([(0.6, 11), (0.02, 70)])
        #expect(result.count == 1)
    }

    @Test func conRuidoDeFondoTambienEncuentraLasPausas() {
        // El «silencio» es ruido constante a 0,3: cuenta como pausa porque está junto al mínimo.
        let result = cuts([(0.7, 11), (0.3, 1), (0.7, 3)])
        #expect(result.count == 1)
    }
}

@Suite("Dictados largos")
struct LongDictationTests {
    @Test func guardaLaUltimaFrase() {
        let split = LongDictation.splitKeepingLastSentence("Hola a todos. Hoy vamos a ver el plan. Lo primero es")
        #expect(split.ready == "Hola a todos. Hoy vamos a ver el plan.")
        #expect(split.held == "Lo primero es")
        let closed = LongDictation.splitKeepingLastSentence("Uno. Dos.")
        #expect(closed.ready == "Uno.")
        #expect(closed.held == "Dos.")
        #expect(LongDictation.splitKeepingLastSentence("sin puntos todavía").ready == "")
    }

    @Test func noCortaEnLosPuntosDeUnCorreo() {
        let split = LongDictation.splitKeepingLastSentence("Escribe a kevin@gmail.com cuando puedas")
        #expect(split.ready == "")
    }

    @Test func uneLosBloques() {
        #expect(LongDictation.join("Quiero que el agente.", "Pueda editar.") == "Quiero que el agente. Pueda editar.")
        #expect(LongDictation.joinPolished(["Hola.", "", "¿Qué tal?"]) == "Hola. ¿Qué tal?")
        #expect(LongDictation.joinPolished(["Pasos:\n1. Abrir", "2. Cerrar"]) == "Pasos:\n1. Abrir\n2. Cerrar")
        #expect(LongDictation.joinPolished(["Uno.\n\nDos.", "Tres."]) == "Uno.\n\nDos.\n\nTres.")
    }
}

@Suite("Continuar lo ya escrito")
struct ContextJoinerTests {
    @Test func continuaLaFraseEnMinuscula() {
        #expect(ContextJoiner.adapt("Lo revises mañana.", after: "Te lo mando para que") == " lo revises mañana.")
        #expect(ContextJoiner.adapt("Y también el viernes.", after: "Voy el lunes, ") == "y también el viernes.")
    }

    @Test func fraseNuevaTrasUnPunto() {
        #expect(ContextJoiner.adapt("Mañana te llamo.", after: "Hola Marta.") == " Mañana te llamo.")
        #expect(ContextJoiner.adapt("Mañana te llamo.", after: "Hola Marta. ") == "Mañana te llamo.")
        #expect(ContextJoiner.adapt("Mañana te llamo.", after: "Hola\n") == "Mañana te llamo.")
    }

    @Test func respetaNombresYSiglas() {
        #expect(ContextJoiner.adapt("iPhone nuevo", after: "tengo un") == " iPhone nuevo")
        #expect(ContextJoiner.adapt("API de pagos", after: "falla la") == " API de pagos")
        #expect(ContextJoiner.adapt("Marta viene", after: "creo que", keepingCase: ["Marta"]) == " Marta viene")
        #expect(ContextJoiner.adapt("I think so", after: "yes,") == " I think so")
    }

    @Test func sinContextoNoCambiaNada() {
        #expect(ContextJoiner.adapt("Hola.", after: nil) == "Hola.")
        #expect(ContextJoiner.adapt("Hola.", after: "") == "Hola.")
        #expect(ContextJoiner.adapt("¿Vienes?", after: "oye") == " ¿Vienes?")
    }
}

@Suite("Fidelidad")
struct FaithfulnessTests {
    @Test func aceptaCorreccionesYFormato() {
        #expect(PolishGuard.isFaithful(
            "Quedamos el viernes a las 6 en la cafetería.",
            to: ["Quedamos el viernes a las cinco, no, perdón, a las seis, en la cafetería."]
        ))
        #expect(PolishGuard.isFaithful(
            "Haz un commit con los cambios y luego abre un pull request contra main.",
            to: ["haz un comit con los cambios y luego abre un pul ricuest contra main"]
        ))
    }

    @Test func rechazaUnaRespuesta() {
        #expect(!PolishGuard.isFaithful(
            "La capital de Francia es París y tiene unos dos millones de habitantes.",
            to: ["cuál es la capital de Francia y cuántos habitantes tiene"]
        ))
    }

    @Test func quitaLoQueYaEstabaEscrito() {
        let before = "Hola Marta. También quiero que se pueda editar todo."
        #expect(PolishGuard.removingEcho(of: before, from: "También quiero que se pueda editar todo. Entonces agrega eso.") == "Entonces agrega eso.")
        #expect(PolishGuard.removingEcho(of: before, from: "Entonces agrega eso.") == "Entonces agrega eso.")
        #expect(PolishGuard.removingEcho(of: "Hola.", from: "Hola. Adiós.") == "Hola. Adiós.")
    }

    @Test func detectaElEcoDeLaPista() {
        #expect(Snippets.isContained("el agente.", in: "Quiero ver lo que hace el agente"))
        #expect(!Snippets.isContained("la gente", in: "Quiero ver lo que hace el agente"))
    }

    @Test func elContextoNoCuentaComoInventado() {
        #expect(PolishGuard.isFaithful(
            "Quiero que el agente pueda editar archivos.",
            to: ["quiero que la gente pueda editar archivos", "Estoy mejorando mi agente de código."]
        ))
    }
}

@Suite("Contexto en el mensaje")
struct PromptContextTests {
    @Test func incluyeLoDeAntesDelCursor() {
        var input = PolishInput(transcript: "lo revises mañana", locale: Locale(identifier: "es_ES"), appName: "Notas")
        input.textBefore = "Te lo mando para que"
        input.previousDictation = "Otra cosa."
        let message = PolishPrompt.smartMessage(for: input)
        #expect(message == "Language: Spanish.\nApp: Notas\nText before the cursor: Te lo mando para que\nwhisper: lo revises mañana")
    }

    @Test func sinCampoUsaElDictadoAnterior() {
        var input = PolishInput(transcript: "y también el viernes", locale: Locale(identifier: "es_ES"), style: .casual)
        input.previousDictation = "Voy el lunes"
        let message = PolishPrompt.smartMessage(for: input)
        #expect(message.contains("Style: Chat message"))
        #expect(message.contains("Previous dictation: Voy el lunes\nwhisper: y también el viernes"))
    }

    @Test func recortaElContextoLargo() {
        let long = String(repeating: "palabra ", count: 200)
        let tail = PolishPrompt.tail(long)
        #expect(tail.count <= PolishPrompt.contextLimit)
        #expect(tail.hasPrefix("palabra"))
    }

    @Test func lasInstruccionesCabenEnElLimiteGratuito() {
        // Unos 800 tokens: con 8.000 por minuto, salen unos nueve dictados pulidos por minuto y modelo.
        #expect(GroqClient.estimatedTokens(PolishPrompt.smartInstructions) < 1150)
    }

    @Test func qwenTieneTopeDeSalida() {
        // Un texto normal cabe y se pide lo justo; uno enorme se deja para los otros modelos.
        #expect(GroqChatModel.qwen.outputBudget(forTextOf: 100) == 230)
        #expect(GroqChatModel.qwen.outputBudget(forTextOf: 700) == nil)
        #expect(GroqChatModel.gptOSS20.outputBudget(forTextOf: 700) == 1450)
    }

    @Test func senalesParaUsarLaIA() {
        #expect(SmartFormatter.needsLanguageModel("hola coma qué tal", alternative: nil))
        #expect(SmartFormatter.needsLanguageModel("se escribe C-L-A-U-D-E", alternative: nil))
        #expect(SmartFormatter.needsLanguageModel("por ejemplo hola mundo", alternative: nil))
        #expect(!SmartFormatter.needsLanguageModel("Sí, ya voy para allá.", alternative: nil))
    }
}
