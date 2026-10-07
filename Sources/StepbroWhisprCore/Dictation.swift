import Foundation

/// Un dictado ya entregado.
public struct Dictation: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    public var date: Date
    /// Segundos hablando; nil en dictados guardados antes de medirlo.
    public var duration: TimeInterval?
    /// App donde se pegó, si se conoce.
    public var appName: String?
    /// Identificador de esa app, para enseñar su icono (los dictados antiguos no lo tienen).
    public var bundleID: String?

    public init(
        id: UUID = UUID(), text: String, date: Date, duration: TimeInterval? = nil,
        appName: String? = nil, bundleID: String? = nil
    ) {
        self.id = id
        self.text = text
        self.date = date
        self.duration = duration
        self.appName = appName
        self.bundleID = bundleID
    }

    public var wordCount: Int { text.wordCount }
}

/// Cifras que se enseñan en Inicio.
public struct DictationStats: Equatable, Sendable {
    /// Velocidad media al teclear, para calcular el tiempo ahorrado.
    public static let typingWordsPerMinute = 40.0

    public var totalWords: Int
    public var totalSeconds: TimeInterval

    public init(totalWords: Int = 0, totalSeconds: TimeInterval = 0) {
        self.totalWords = totalWords
        self.totalSeconds = totalSeconds
    }

    public mutating func add(_ dictation: Dictation) {
        totalWords += dictation.wordCount
        totalSeconds += dictation.duration ?? 0
    }

    public var wordsPerMinute: Int? {
        guard totalSeconds >= 10 else { return nil }
        return Int((Double(totalWords) / (totalSeconds / 60)).rounded())
    }

    public var minutesSaved: Int {
        max(0, Int((Double(totalWords) / Self.typingWordsPerMinute - totalSeconds / 60).rounded()))
    }

    /// Días seguidos (hasta hoy o ayer) con al menos un dictado.
    public static func streak(in history: [Dictation], now: Date = .now, calendar: Calendar = .current) -> Int {
        let days = Set(history.map { calendar.startOfDay(for: $0.date) })
        var day = calendar.startOfDay(for: now)
        if !days.contains(day) {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        var streak = 0
        while days.contains(day) {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return streak
    }

    public static func wordsInLastWeek(of history: [Dictation], now: Date = .now, calendar: Calendar = .current) -> Int {
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? .distantPast
        return history.filter { $0.date > weekAgo }.reduce(0) { $0 + $1.wordCount }
    }
}

extension String {
    public var wordCount: Int { split(whereSeparator: \.isWhitespace).count }
}
