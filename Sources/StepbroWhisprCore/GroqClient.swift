import Foundation

/// Modelos de Groq para transcribir la voz.
public enum WhisperModel: String, CaseIterable, Identifiable, Codable, Sendable {
    case turbo = "whisper-large-v3-turbo"
    case large = "whisper-large-v3"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .turbo: "Whisper Large v3 Turbo"
        case .large: "Whisper Large v3"
        }
    }

    public var summary: String {
        switch self {
        case .turbo: "Muy rápido y preciso. El recomendado."
        case .large: "La máxima precisión, algo más lento."
        }
    }
}

/// Modelos de Groq para pulir el texto.
public enum GroqChatModel: String, CaseIterable, Identifiable, Codable, Sendable {
    case qwen = "qwen/qwen3.8-27b"
    case gptOSS20 = "openai/gpt-oss-20b"
    case gptOSS120 = "openai/gpt-oss-120b"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .gptOSS120: "GPT OSS 120B"
        case .gptOSS20: "GPT OSS 20B"
        case .qwen: "Qwen 3.8 27B"
        }
    }

    public var summary: String {
        switch self {
        case .qwen: "El recomendado: el más rápido y el más fiel a tus palabras."
        case .gptOSS20: "Rápido, pero aplica menos correcciones."
        case .gptOSS120: "Razona más, pero a veces cambia o quita palabras."
        }
    }

    /// Tokens de salida que admite por petición en la cuenta gratuita de Groq, si tiene tope.
    /// Qwen solo da 1.000 por minuto, y cuenta lo que se le pide como máximo, no lo que escribe.
    public var outputLimit: Int? {
        self == .qwen ? 1000 : nil
    }

    /// Máximo de tokens de salida que pedir para pulir un texto de `tokens` tokens: lo justo,
    /// o nil si el texto no cabe en el tope del modelo.
    public func outputBudget(forTextOf tokens: Int) -> Int? {
        let needed = tokens * 3 / 2 + 80
        guard let outputLimit else { return min(4096, needed + 320) }
        return needed <= outputLimit ? needed : nil
    }

    /// Este modelo primero y después los demás, para cuando uno llega a su límite o va lento.
    public var withFallbacks: [GroqChatModel] {
        [self] + Self.allCases.filter { $0 != self }
    }

    /// Parámetros de razonamiento: se piden respuestas rápidas y sin el razonamiento en el texto.
    fileprivate var reasoning: (effort: String, includeReasoning: Bool?, format: String?) {
        switch self {
        case .gptOSS120, .gptOSS20: ("low", false, nil)
        case .qwen: ("none", nil, "hidden")
        }
    }
}

public enum GroqError: LocalizedError, Equatable {
    case missingKey
    case invalidKey
    /// `retryAfter`: segundos hasta que Groq vuelve a aceptar peticiones, si lo dice.
    case rateLimited(retryAfter: TimeInterval? = nil)
    case overloaded
    case truncated
    case emptyResponse
    /// La respuesta no llegó a tiempo (la conexión existe, pero va lenta).
    case timedOut
    case server(status: Int, message: String?)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .missingKey: "Falta la clave de Groq."
        case .invalidKey: "La clave de Groq no es válida."
        case .rateLimited: "Has llegado al límite de Groq; espera un poco."
        case .overloaded: "Groq está saturado ahora mismo."
        case .truncated: "La respuesta de Groq se cortó."
        case .emptyResponse: "Groq no devolvió texto."
        case .timedOut: "Groq tardó demasiado en responder."
        case .server(let status, let message): "Error de Groq (\(status)): \(message ?? "sin detalles")"
        case .network(let message): "Sin conexión con Groq: \(message)"
        }
    }
}

/// Lo que queda del límite por minuto de un modelo, según las cabeceras de la respuesta.
public struct GroqRateLimit: Equatable, Sendable {
    /// Tokens por minuto que admite el modelo.
    public var limitTokens: Int?
    public var remainingTokens: Int?
    /// Segundos hasta que el límite de tokens vuelve a estar entero.
    public var resetTokens: TimeInterval?

    public init(limitTokens: Int? = nil, remainingTokens: Int? = nil, resetTokens: TimeInterval? = nil) {
        self.limitTokens = limitTokens
        self.remainingTokens = remainingTokens
        self.resetTokens = resetTokens
    }

    /// Tokens disponibles pasados `elapsed` segundos: el límite se va rellenando poco a poco.
    public func available(after elapsed: TimeInterval) -> Int? {
        guard let remainingTokens else { return nil }
        guard let limitTokens, let resetTokens, resetTokens > 0 else { return remainingTokens }
        let refilled = Double(limitTokens - remainingTokens) * min(1, max(0, elapsed) / resetTokens)
        return remainingTokens + Int(refilled)
    }

    init(headers: [String: String]) {
        limitTokens = headers["x-ratelimit-limit-tokens"].flatMap(Int.init)
        remainingTokens = headers["x-ratelimit-remaining-tokens"].flatMap(Int.init)
        resetTokens = headers["x-ratelimit-reset-tokens"].flatMap(Self.seconds)
    }

    /// Groq escribe las duraciones como «997ms», «11.1s» o «10m4.8s».
    static func seconds(_ text: String) -> TimeInterval? {
        var total = 0.0
        var number = ""
        var unit = ""
        var found = false
        func flush() -> Bool {
            guard let value = Double(number) else { return number.isEmpty && unit.isEmpty }
            switch unit {
            case "ms": total += value / 1000
            case "s", "": total += value
            case "m": total += value * 60
            case "h": total += value * 3600
            default: return false
            }
            found = true
            return true
        }
        for character in text.trimmingCharacters(in: .whitespaces) {
            if character.isNumber || character == "." {
                if !unit.isEmpty {
                    guard flush() else { return nil }
                    number = ""
                    unit = ""
                }
                number.append(character)
            } else {
                unit.append(character)
            }
        }
        guard flush(), found else { return nil }
        return total
    }
}

/// Respuesta de un modelo de texto, con lo que queda de su límite.
public struct GroqChatReply: Equatable, Sendable {
    public var text: String
    public var limit: GroqRateLimit
}

/// Cliente mínimo de la API de Groq (compatible con OpenAI).
public struct GroqClient: Sendable {
    public static let baseURL = URL(string: "https://api.groq.com/openai/v1")!

    public var apiKey: String
    public var timeout: TimeInterval
    public var session: URLSession

    public init(apiKey: String, timeout: TimeInterval = 10, session: URLSession = GroqClient.primarySession) {
        self.apiKey = apiKey
        self.timeout = timeout
        self.session = session
    }

    /// Conexión habitual con Groq, que se mantiene abierta entre dictados.
    public static let primarySession = makeSession()
    /// Segunda conexión, independiente: si la primera se atasca (wifi con cortes), se repite la petición por aquí.
    public static let backupSession = makeSession()

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: configuration)
    }

    /// Comprueba la clave sin gastar nada: pide la lista de modelos.
    public func validateKey() async throws {
        let key = try validKey()
        var request = URLRequest(url: Self.baseURL.appending(path: "models"), timeoutInterval: timeout)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, status, headers) = try await send(request)
        try Self.checkStatus(data: data, status: status, headers: headers)
    }

    // MARK: - Transcripción

    /// Transcribe un archivo de audio. `prompt` orienta la ortografía (diccionario).
    public func transcribe(audio: Data, filename: String, model: WhisperModel, language: String?, prompt: String?) async throws -> String {
        let request = try makeTranscriptionRequest(audio: audio, filename: filename, model: model, language: language, prompt: prompt)
        let (data, status, headers) = try await send(request)
        return try Self.parseTranscription(data: data, status: status, headers: headers)
    }

    func makeTranscriptionRequest(audio: Data, filename: String, model: WhisperModel, language: String?, prompt: String?) throws -> URLRequest {
        let key = try validKey()
        let boundary = "stepbro-\(UUID().uuidString)"
        var request = URLRequest(url: Self.baseURL.appending(path: "audio/transcriptions"), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var form = MultipartForm(boundary: boundary)
        form.addField("model", model.rawValue)
        form.addField("response_format", "json")
        form.addField("temperature", "0")
        if let language, !language.isEmpty { form.addField("language", language) }
        if let prompt, !prompt.isEmpty { form.addField("prompt", prompt) }
        let contentType = filename.lowercased().hasSuffix(".wav") ? "audio/wav" : "audio/mp4"
        form.addFile("file", filename: filename, contentType: contentType, data: audio)
        request.httpBody = form.finish()
        return request
    }

    static func parseTranscription(data: Data, status: Int, headers: [String: String] = [:]) throws -> String {
        try checkStatus(data: data, status: status, headers: headers)
        struct Response: Decodable { let text: String }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw GroqError.server(status: status, message: "respuesta ilegible")
        }
        return response.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Pulido

    public func complete(model: GroqChatModel, system: String, user: String, maxTokens: Int = 4096) async throws -> GroqChatReply {
        let request = try makeChatRequest(model: model, system: system, user: user, maxTokens: maxTokens)
        let (data, status, headers) = try await send(request)
        let text = try Self.parseChat(data: data, status: status, headers: headers)
        return GroqChatReply(text: text, limit: GroqRateLimit(headers: headers))
    }

    /// Tokens que gasta una petición, a ojo: unos 3 caracteres y medio por token.
    public static func estimatedTokens(_ text: String) -> Int {
        text.utf8.count * 2 / 7 + 1
    }

    func makeChatRequest(model: GroqChatModel, system: String, user: String, maxTokens: Int) throws -> URLRequest {
        let key = try validKey()
        var request = URLRequest(url: Self.baseURL.appending(path: "chat/completions"), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let reasoning = model.reasoning
        let body = ChatRequest(
            model: model.rawValue,
            messages: [.init(role: "system", content: system), .init(role: "user", content: user)],
            // Sin azar: el mismo dictado da siempre el mismo texto.
            temperature: 0,
            maxCompletionTokens: maxTokens,
            reasoningEffort: reasoning.effort,
            includeReasoning: reasoning.includeReasoning,
            reasoningFormat: reasoning.format
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)
        return request
    }

    static func parseChat(data: Data, status: Int, headers: [String: String] = [:]) throws -> String {
        try checkStatus(data: data, status: status, headers: headers)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let response = try? decoder.decode(ChatResponse.self, from: data),
              let choice = response.choices.first
        else { throw GroqError.server(status: status, message: "respuesta ilegible") }
        if choice.finishReason == "length" { throw GroqError.truncated }
        let text = (choice.message.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw GroqError.emptyResponse }
        return text
    }

    // MARK: - Común

    private func validKey() throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw GroqError.missingKey }
        return key
    }

    private func send(_ request: URLRequest) async throws -> (Data, Int, [String: String]) {
        do {
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            var headers: [String: String] = [:]
            for (name, value) in http?.allHeaderFields ?? [:] {
                if let name = name as? String, let value = value as? String { headers[name.lowercased()] = value }
            }
            return (data, http?.statusCode ?? 0, headers)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw GroqError.timedOut
        } catch {
            throw GroqError.network(error.localizedDescription)
        }
    }

    private static func checkStatus(data: Data, status: Int, headers: [String: String] = [:]) throws {
        guard !(200..<300).contains(status) else { return }
        struct ErrorResponse: Decodable {
            struct Detail: Decodable { let message: String? }
            let error: Detail
        }
        let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error.message
        switch status {
        case 401: throw GroqError.invalidKey
        case 429:
            throw GroqError.rateLimited(
                retryAfter: headers["retry-after"].flatMap(Double.init) ?? GroqRateLimit(headers: headers).resetTokens
            )
        case 498, 500, 502, 503, 504: throw GroqError.overloaded
        default: throw GroqError.server(status: status, message: message)
        }
    }
}

// MARK: - JSON y formularios

struct ChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let maxCompletionTokens: Int
    let reasoningEffort: String
    let includeReasoning: Bool?
    let reasoningFormat: String?
}

struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
        let finishReason: String?
    }

    let choices: [Choice]
}

/// Cuerpo multipart/form-data para subir el audio.
struct MultipartForm {
    let boundary: String
    private var body = Data()

    init(boundary: String) {
        self.boundary = boundary
    }

    mutating func addField(_ name: String, _ value: String) {
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
    }

    mutating func addFile(_ name: String, filename: String, contentType: String, data: Data) {
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(contentType)\r\n\r\n")
        body.append(data)
        body.append("\r\n")
    }

    func finish() -> Data {
        var result = body
        result.append("--\(boundary)--\r\n")
        return result
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
