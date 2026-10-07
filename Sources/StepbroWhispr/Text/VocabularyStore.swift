import Foundation
import Observation
import StepbroWhisprCore

/// Diccionario, atajos de texto y estilos por app.
/// Se guardan en ~/Library/Application Support/stepbro whispr/vocabulario.json.
@MainActor
@Observable
final class VocabularyStore {
    var entries: [VocabularyEntry] { didSet { save() } }
    var snippets: [Snippet] { didSet { save() } }
    private var styles: [String: WritingStyle] { didSet { save() } }

    private struct File: Codable {
        var entries: [VocabularyEntry] = []
        var snippets: [Snippet] = []
        var styles: [String: WritingStyle] = [:]
    }

    init() {
        let file = Self.load()
        entries = file.entries
        snippets = file.snippets
        styles = file.styles
    }

    func style(for category: AppCategory) -> WritingStyle {
        styles[category.rawValue] ?? category.defaultStyle
    }

    func setStyle(_ style: WritingStyle, for category: AppCategory) {
        styles[category.rawValue] = style
    }

    /// Palabras que se le sugieren al reconocimiento de voz para que las entienda mejor.
    var hints: [String] {
        // Las palabras corrientes que se confunden con un término van al final, como contrapeso:
        // sin ellas, Whisper escribe «Claude» cada vez que oye «cloud».
        entries.map(\.term) + snippets.map(\.trigger) + entries.flatMap(\.confusedWith)
    }

    // MARK: - Archivo

    private static var fileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "stepbro whispr", directoryHint: .isDirectory)
            .appending(path: "vocabulario.json")
    }

    private static func load() -> File {
        var file = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(File.self, from: $0) } ?? File()
        // Una sola vez: nombres de IA que el reconocimiento de voz confunde con palabras corrientes.
        // Quedan en Diccionario, donde se pueden cambiar o borrar.
        let flag = "seededAITerms"
        if !UserDefaults.standard.bool(forKey: flag) {
            UserDefaults.standard.set(true, forKey: flag)
            let known = Set(file.entries.map { $0.term.lowercased() })
            file.entries += Self.starterTerms.filter { !known.contains($0.term.lowercased()) }
            write(file)
        }
        let confusedFlag = "seededConfusedWords"
        if !UserDefaults.standard.bool(forKey: confusedFlag) {
            UserDefaults.standard.set(true, forKey: confusedFlag)
            if let index = file.entries.firstIndex(where: { $0.term == "Claude" }), file.entries[index].confusedWith.isEmpty {
                file.entries[index].confusedWith = ["cloud"]
                write(file)
            }
        }
        return file
    }

    /// Los términos de varias palabras van antes, para que «cloud code» no se quede en «Claude» a medias.
    private static let starterTerms = [
        VocabularyEntry(term: "Claude Code", heardAs: ["cloud code", "clod code", "claud code", "clau code", "cloud cod"]),
        VocabularyEntry(term: "Claude Opus", heardAs: ["cloud opus", "clod opus", "claud opus"]),
        VocabularyEntry(term: "Claude Sonnet", heardAs: ["cloud sonnet", "cloud soneto", "claude soneto", "clod sonnet"]),
        VocabularyEntry(term: "Claude", heardAs: ["claud", "clod"], confusedWith: ["cloud"]),
        VocabularyEntry(term: "Sonnet", heardAs: ["sonet"]),
        VocabularyEntry(term: "Anthropic", heardAs: ["antropic", "antrópic", "anthropics"]),
        VocabularyEntry(term: "Groq", heardAs: ["groc", "grock"]),
        VocabularyEntry(term: "ChatGPT", heardAs: ["chat gpt", "chat g p t", "chat yipiti"]),
    ]

    private func save() {
        Self.write(File(entries: entries, snippets: snippets, styles: styles))
    }

    private static func write(_ file: File) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(file).write(to: fileURL, options: .atomic)
        } catch {
            SpeechEngine.log.error("no se pudo guardar el vocabulario: \(error.localizedDescription, privacy: .public)")
        }
    }
}
