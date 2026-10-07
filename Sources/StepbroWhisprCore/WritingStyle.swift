import Foundation

/// Tono con el que se pule el texto.
public enum WritingStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case formal
    case normal
    case casual
    case technical

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .formal: "Formal"
        case .normal: "Normal"
        case .casual: "Casual"
        case .technical: "Técnico"
        }
    }

    public var summary: String {
        switch self {
        case .formal: "Frases completas y cuidadas."
        case .normal: "Tal como hablas, bien puntuado."
        case .casual: "Corto y natural, como en un chat."
        case .technical: "Respeta código, comandos y siglas."
        }
    }

    /// Instrucción para el modelo de lenguaje.
    var instruction: String {
        switch self {
        case .formal:
            "Formal: complete sentences with careful punctuation, still in the speaker's own words. No greetings or sign-offs that were not dictated."
        case .normal:
            "Natural: keep the speaker's own wording, with correct punctuation and capitalization."
        case .casual:
            "Chat message: keep it informal. A single short sentence does not end with a period."
        case .technical:
            "Technical: write code identifiers, commands, file names, flags and product names the way developers write them (\"comit\" -> \"commit\", \"punto js\" -> \".js\", \"guion guion help\" -> \"--help\")."
        }
    }
}

/// Tipo de app donde se va a pegar, para elegir el estilo.
public enum AppCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case messages
    case email
    case code
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .messages: "Mensajes"
        case .email: "Correo"
        case .code: "Código"
        case .other: "Resto de apps"
        }
    }

    public var examples: String {
        switch self {
        case .messages: "WhatsApp, Mensajes, Slack, Telegram, Discord"
        case .email: "Mail, Outlook, Spark"
        case .code: "Xcode, VS Code, Cursor, Terminal"
        case .other: "Notas, Pages, navegadores…"
        }
    }

    public var defaultStyle: WritingStyle {
        switch self {
        case .messages: .casual
        case .email: .formal
        case .code: .technical
        case .other: .normal
        }
    }

    public init(bundleID: String?) {
        guard let bundleID = bundleID?.lowercased() else {
            self = .other
            return
        }
        if Self.messageApps.contains(bundleID) {
            self = .messages
        } else if Self.emailApps.contains(bundleID) {
            self = .email
        } else if Self.codeApps.contains(bundleID) || Self.codePrefixes.contains(where: bundleID.hasPrefix) {
            self = .code
        } else {
            self = .other
        }
    }

    private static let messageApps: Set<String> = [
        "com.apple.mobilesms", "net.whatsapp.whatsapp", "desktop.whatsapp", "com.tinyspeck.slackmacgap",
        "com.hnc.discord", "ru.keepcoder.telegram", "org.telegram.desktop", "com.facebook.archon",
        "org.whispersystems.signal-desktop", "com.microsoft.teams2", "com.microsoft.teams",
    ]

    private static let emailApps: Set<String> = [
        "com.apple.mail", "com.microsoft.outlook", "com.readdle.smartemail-mac",
        "com.superhuman.electron", "com.mimestream.mimestream", "it.bloop.airmail2",
    ]

    private static let codeApps: Set<String> = [
        "com.apple.dt.xcode", "com.microsoft.vscode", "com.microsoft.vscodeinsiders",
        "com.todesktop.230313mzl4w4u92", "dev.zed.zed", "com.apple.terminal", "com.googlecode.iterm2",
        "com.mitchellh.ghostty", "dev.warp.warp-stable", "com.stepbro.terminal", "com.sublimetext.4",
        "com.exafunction.windsurf", "com.panic.nova",
    ]

    private static let codePrefixes = ["com.jetbrains."]
}

public enum StyleFormatter {
    /// Retoques finales que no dependen del modelo de lenguaje.
    public static func finish(_ text: String, style: WritingStyle) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard style == .casual else { return result }
        // En un chat, una frase corta suelta no lleva punto final.
        let sentences = result.split(whereSeparator: { ".!?¿¡".contains($0) }).filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        if sentences.count == 1, result.count <= 140, result.hasSuffix("."), !result.hasSuffix("...") {
            result.removeLast()
        }
        return result
    }
}
