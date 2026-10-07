import AppKit
import StepbroWhisprCore

/// Tecla que hay que mantener pulsada para dictar.
enum Hotkey: String, CaseIterable, Identifiable {
    case fn
    case rightOption
    case rightCommand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fn: "Fn (globo)"
        case .rightOption: "⌥ Opción derecha"
        case .rightCommand: "⌘ Comando derecho"
        }
    }

    var shortName: String {
        switch self {
        case .fn: "Fn"
        case .rightOption: "⌥ derecha"
        case .rightCommand: "⌘ derecho"
        }
    }

    /// Lo que se dibuja en la tecla.
    var keySymbol: String {
        switch self {
        case .fn: "fn"
        case .rightOption: "⌥"
        case .rightCommand: "⌘"
        }
    }

    var longName: String {
        switch self {
        case .fn: "Fn (globo)"
        case .rightOption: "Opción derecha"
        case .rightCommand: "Comando derecho"
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .fn: 63
        case .rightOption: 61
        case .rightCommand: 54
        }
    }

    /// Bit del modificador concreto (lado derecho incluido) en `NSEvent.modifierFlags`.
    var deviceMask: UInt {
        switch self {
        case .fn: NSEvent.ModifierFlags.function.rawValue
        case .rightOption: 0x40   // NX_DEVICERALTKEYMASK
        case .rightCommand: 0x10  // NX_DEVICERCMDKEYMASK
        }
    }
}

/// Motor de dictado: todo en el Mac (Apple) o en la nube (Groq).
enum DictationEngine: String, CaseIterable, Identifiable {
    case apple
    case groq

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: "Apple"
        case .groq: "Groq"
        }
    }

    var symbol: String {
        switch self {
        case .apple: "apple.logo"
        case .groq: "bolt.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .apple: "En tu Mac"
        case .groq: "En la nube"
        }
    }

    var summary: String {
        switch self {
        case .apple: "Privado, sin internet y gratis."
        case .groq: "Más preciso con nombres y términos técnicos. Necesita una clave."
        }
    }
}

/// Ajustes guardados en UserDefaults. Las vistas usan las mismas claves con @AppStorage.
enum Preferences {
    static let hotkeyKey = "hotkey"
    static let languageKey = "language"
    static let polishKey = "polishWithAI"
    static let trailingSpaceKey = "trailingSpace"
    static let soundsKey = "sounds"
    static let showInMenuBarKey = "showInMenuBar"
    static let alwaysShowBarKey = "alwaysShowBar"
    static let userNameKey = "userName"
    static let onboardingDoneKey = "onboardingDone"
    static let microphoneKey = "microphoneUID"
    static let engineKey = "engine"
    static let translateKey = "translateTo"
    /// Valor de `language` para detectar el idioma automáticamente (español e inglés).
    static let automaticLanguage = "auto"
    static let groqWhisperModelKey = "groqWhisperModel"
    static let groqChatModelKey = "groqChatModel"
    static let useContextKey = "useContext"
    /// Qwen pasó a ser el modelo recomendado: se elige una vez a quien tenía el anterior.
    private static let qwenDefaultKey = "chatModelMovedToQwen"
    /// Interruptores de versiones anteriores, solo para elegir el motor la primera vez.
    private static let legacyGroqKeys = ["groqTranscribe", "groqPolish"]

    static func registerDefaults() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: engineKey) == nil, legacyGroqKeys.contains(where: defaults.bool(forKey:)) {
            defaults.set(DictationEngine.groq.rawValue, forKey: engineKey)
        }
        if !defaults.bool(forKey: qwenDefaultKey) {
            defaults.set(true, forKey: qwenDefaultKey)
            defaults.removeObject(forKey: groqChatModelKey)
        }
        defaults.register(defaults: [
            hotkeyKey: Hotkey.fn.rawValue,
            languageKey: "",
            polishKey: true,
            trailingSpaceKey: true,
            soundsKey: true,
            showInMenuBarKey: true,
            alwaysShowBarKey: true,
            userNameKey: "",
            onboardingDoneKey: false,
            microphoneKey: "",
            engineKey: DictationEngine.apple.rawValue,
            translateKey: TranslationTarget.none.rawValue,
            groqWhisperModelKey: WhisperModel.turbo.rawValue,
            groqChatModelKey: GroqChatModel.qwen.rawValue,
            useContextKey: true,
        ])
    }

    static var hotkey: Hotkey {
        Hotkey(rawValue: UserDefaults.standard.string(forKey: hotkeyKey) ?? "") ?? .fn
    }

    /// Identificador de idioma; vacío significa "el del sistema".
    static var language: String {
        UserDefaults.standard.string(forKey: languageKey) ?? ""
    }

    /// Nombre de macOS, para proponerlo en la bienvenida.
    static var systemFirstName: String {
        NSFullUserName().split(separator: " ").first.map { String($0).capitalized } ?? ""
    }

    /// UID del micrófono elegido; vacío significa automático.
    static var microphone: String {
        UserDefaults.standard.string(forKey: microphoneKey) ?? ""
    }

    static var polish: Bool { UserDefaults.standard.bool(forKey: polishKey) }
    static var isAutomaticLanguage: Bool { language == automaticLanguage }

    static var translateTo: TranslationTarget {
        TranslationTarget(rawValue: UserDefaults.standard.string(forKey: translateKey) ?? "") ?? .none
    }

    static var engine: DictationEngine {
        DictationEngine(rawValue: UserDefaults.standard.string(forKey: engineKey) ?? "") ?? .apple
    }
    static var groqWhisperModel: WhisperModel {
        WhisperModel(rawValue: UserDefaults.standard.string(forKey: groqWhisperModelKey) ?? "") ?? .turbo
    }
    static var groqChatModel: GroqChatModel {
        GroqChatModel(rawValue: UserDefaults.standard.string(forKey: groqChatModelKey) ?? "") ?? .qwen
    }
    /// Leer lo que ya hay escrito antes del cursor para continuar la frase.
    static var useContext: Bool { UserDefaults.standard.bool(forKey: useContextKey) }
    static var trailingSpace: Bool { UserDefaults.standard.bool(forKey: trailingSpaceKey) }
    static var sounds: Bool { UserDefaults.standard.bool(forKey: soundsKey) }
}
