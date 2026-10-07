import Foundation
import Testing
@testable import StepbroWhisprCore

@Suite("Cliente de Groq")
struct GroqClientTests {
    let client = GroqClient(apiKey: "gsk_test")

    @Test func peticionDeTranscripcion() throws {
        let audio = Data([0x52, 0x49, 0x46, 0x46])
        let request = try client.makeTranscriptionRequest(
            audio: audio, filename: "dictado.wav", model: .turbo, language: "es", prompt: "stepbro, iPhone."
        )
        #expect(request.url?.absoluteString == "https://api.groq.com/openai/v1/audio/transcriptions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer gsk_test")
        let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
        #expect(contentType.hasPrefix("multipart/form-data; boundary="))

        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body.contains("name=\"model\"\r\n\r\nwhisper-large-v3-turbo\r\n"))
        #expect(body.contains("name=\"language\"\r\n\r\nes\r\n"))
        #expect(body.contains("name=\"prompt\"\r\n\r\nstepbro, iPhone.\r\n"))
        #expect(body.contains("name=\"file\"; filename=\"dictado.wav\""))
        #expect(body.contains("RIFF"))
    }

    @Test func audioComprimido() throws {
        let request = try client.makeTranscriptionRequest(
            audio: Data([0, 1]), filename: "stepbro-1.m4a", model: .turbo, language: "es", prompt: nil
        )
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body.contains("filename=\"stepbro-1.m4a\"\r\nContent-Type: audio/mp4"))
    }

    @Test func peticionDePulidoConGptOSS() throws {
        let request = try client.makeChatRequest(model: .gptOSS120, system: "Instrucciones", user: "Hola", maxTokens: 4096)
        #expect(request.url?.absoluteString == "https://api.groq.com/openai/v1/chat/completions")
        let json = try #require(try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        #expect(json["model"] as? String == "openai/gpt-oss-120b")
        #expect(json["reasoning_effort"] as? String == "low")
        #expect(json["include_reasoning"] as? Bool == false)
        #expect(json["reasoning_format"] == nil)
        #expect(json["max_completion_tokens"] as? Int == 4096)
        #expect(json["temperature"] as? Double == 0)
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["system", "user"])
    }

    @Test func peticionDePulidoConQwen() throws {
        let request = try client.makeChatRequest(model: .qwen, system: "a", user: "b", maxTokens: 100)
        let json = try #require(try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        #expect(json["model"] as? String == "qwen/qwen3.8-27b")
        #expect(json["reasoning_effort"] as? String == "none")
        #expect(json["reasoning_format"] as? String == "hidden")
        // Son excluyentes: Groq rechaza include_reasoning junto a reasoning_format.
        #expect(json["include_reasoning"] == nil)
    }

    @Test func leeLasRespuestas() throws {
        let transcription = Data(#"{"text":" Hola, Marta. ","x_groq":{"id":"req_1"}}"#.utf8)
        #expect(try GroqClient.parseTranscription(data: transcription, status: 200) == "Hola, Marta.")

        let chat = Data(#"{"choices":[{"index":0,"message":{"role":"assistant","content":"Hola, Marta."},"finish_reason":"stop"}]}"#.utf8)
        #expect(try GroqClient.parseChat(data: chat, status: 200) == "Hola, Marta.")

        let cut = Data(#"{"choices":[{"message":{"content":"Hol"},"finish_reason":"length"}]}"#.utf8)
        #expect(throws: GroqError.truncated) { try GroqClient.parseChat(data: cut, status: 200) }
    }

    @Test func errores() {
        let body = Data(#"{"error":{"message":"Invalid API Key","type":"invalid_request_error"}}"#.utf8)
        #expect(throws: GroqError.invalidKey) { try GroqClient.parseChat(data: body, status: 401) }
        #expect(throws: GroqError.rateLimited(retryAfter: nil)) { try GroqClient.parseChat(data: body, status: 429) }
        #expect(throws: GroqError.rateLimited(retryAfter: 4)) {
            try GroqClient.parseChat(data: body, status: 429, headers: ["retry-after": "4"])
        }
        #expect(throws: GroqError.overloaded) { try GroqClient.parseTranscription(data: body, status: 503) }
        #expect(throws: GroqError.server(status: 400, message: "Invalid API Key")) {
            try GroqClient.parseChat(data: body, status: 400)
        }
    }

    @Test func leeLosLimites() {
        #expect(GroqRateLimit.seconds("997ms") == 0.997)
        #expect(GroqRateLimit.seconds("11.1s") == 11.1)
        #expect(GroqRateLimit.seconds("10m4.8s") == 604.8)
        #expect(GroqRateLimit.seconds("pronto") == nil)
        let limit = GroqRateLimit(headers: [
            "x-ratelimit-limit-tokens": "8000", "x-ratelimit-remaining-tokens": "2000", "x-ratelimit-reset-tokens": "45s",
        ])
        #expect(limit == GroqRateLimit(limitTokens: 8000, remainingTokens: 2000, resetTokens: 45))
        // El límite se rellena poco a poco: a los 15 s ha vuelto un tercio de lo gastado.
        #expect(limit.available(after: 0) == 2000)
        #expect(limit.available(after: 15) == 4000)
        #expect(limit.available(after: 90) == 8000)
    }

    @Test func modelosDeReserva() {
        #expect(GroqChatModel.qwen.withFallbacks == [.qwen, .gptOSS20, .gptOSS120])
        #expect(GroqChatModel.gptOSS120.withFallbacks == [.gptOSS120, .qwen, .gptOSS20])
    }

    @Test func sinClaveNoHayPeticion() {
        #expect(throws: GroqError.missingKey) {
            try GroqClient(apiKey: "  ").makeChatRequest(model: .gptOSS20, system: "a", user: "b", maxTokens: 10)
        }
    }
}

@Suite("Whisper o Apple")
struct TranscriptChooserTests {
    @Test func prefiereWhisper() {
        #expect(TranscriptChooser.choose(whisper: "Habla con stepbro.", local: "Habla con step bro.") == "Habla con stepbro.")
    }

    @Test func sinWhisperUsaApple() {
        #expect(TranscriptChooser.choose(whisper: nil, local: "Hola.") == "Hola.")
        #expect(TranscriptChooser.choose(whisper: "  ", local: "Hola.") == "Hola.")
    }

    @Test func descartaLasFrasesInventadasConSilencio() {
        #expect(TranscriptChooser.choose(whisper: "¡Gracias por ver el video!", local: "") == "")
        #expect(TranscriptChooser.choose(whisper: "Subtítulos realizados por la comunidad de Amara.org", local: "") == "")
        #expect(TranscriptChooser.choose(whisper: "Gracias.", local: "Vale, nos vemos.") == "Vale, nos vemos.")
    }

    @Test func quitaLaDespedidaInventadaAlFinal() {
        #expect(TranscriptChooser.choose(whisper: "Ayúdame a que quede bien. Gracias.", local: "Ayúdame a que quede bien") == "Ayúdame a que quede bien.")
        // Si de verdad se dijo, se queda.
        #expect(TranscriptChooser.choose(whisper: "Te lo mando luego. Gracias.", local: "Te lo mando luego, gracias") == "Te lo mando luego. Gracias.")
        #expect(TranscriptChooser.strippingTrailingHallucination("Hola. ¿Qué tal?", reference: "hola") == "Hola. ¿Qué tal?")
    }

    @Test func soloRuido() {
        #expect(TranscriptChooser.wasOnlyNoise(local: "I", seconds: 14))
        #expect(!TranscriptChooser.wasOnlyNoise(local: "", seconds: 2))
        #expect(!TranscriptChooser.wasOnlyNoise(local: "Vale, perfecto", seconds: 14))
    }

    @Test func confiaEnWhisperSiAppleNoEntendioNada() {
        #expect(TranscriptChooser.choose(whisper: "Kubectl get pods.", local: "") == "Kubectl get pods.")
    }

    @Test func descartaWhisperDemasiadoLargo() {
        let invented = String(repeating: "Esto no lo dijo nadie. ", count: 10)
        #expect(TranscriptChooser.choose(whisper: invented, local: "Hola.") == "Hola.")
    }

    @Test func pistaDeOrtografia() {
        #expect(TranscriptChooser.prompt(for: []) == nil)
        #expect(TranscriptChooser.prompt(for: ["stepbro", "iPhone", "stepbro"]) == "stepbro, iPhone.")
    }
}
