import AppKit
import Observation
import StepbroWhisprCore

/// Historial de dictados y estadísticas, guardados en este Mac.
@MainActor
@Observable
final class HistoryStore {
    private static let historyKey = "history"
    private static let totalWordsKey = "statsTotalWords"
    private static let totalSecondsKey = "statsTotalSeconds"
    private static let limit = 500

    private(set) var items: [Dictation] { didSet { saveItems() } }
    private(set) var stats: DictationStats

    init() {
        let defaults = UserDefaults.standard
        items = defaults.data(forKey: Self.historyKey)
            .flatMap { try? JSONDecoder().decode([Dictation].self, from: $0) } ?? []
        stats = DictationStats(
            totalWords: defaults.integer(forKey: Self.totalWordsKey),
            totalSeconds: defaults.double(forKey: Self.totalSecondsKey)
        )
    }

    var streakDays: Int { DictationStats.streak(in: items) }
    var wordsThisWeek: Int { DictationStats.wordsInLastWeek(of: items) }

    func record(_ dictation: Dictation) {
        items.insert(dictation, at: 0)
        if items.count > Self.limit {
            items.removeLast(items.count - Self.limit)
        }
        stats.add(dictation)
        UserDefaults.standard.set(stats.totalWords, forKey: Self.totalWordsKey)
        UserDefaults.standard.set(stats.totalSeconds, forKey: Self.totalSecondsKey)
    }

    func delete(_ dictation: Dictation) {
        items.removeAll { $0.id == dictation.id }
    }

    func clear() {
        items.removeAll()
    }

    func copy(_ dictation: Dictation) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(dictation.text, forType: .string)
    }

    private func saveItems() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
    }
}
