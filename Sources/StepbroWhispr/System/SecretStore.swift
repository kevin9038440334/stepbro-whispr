import Foundation
import Security

/// Guarda secretos (la clave de Groq) en un archivo que solo puede leer tu usuario.
///
/// No se usa el Llavero porque, al firmar la app con un certificado local, macOS la
/// trata como otra app en cada actualización y pide permiso con un aviso que bloquea
/// el arranque hasta que respondes.
enum SecretStore {
    private static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "stepbro whispr", directoryHint: .isDirectory)
    }

    private static func url(for account: String) -> URL {
        directory.appending(path: "\(account).secret")
    }

    static func read(_ account: String) -> String? {
        guard let data = try? Data(contentsOf: url(for: account)) else { return nil }
        let value = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    @discardableResult
    static func save(_ value: String, for account: String) -> Bool {
        guard !value.isEmpty else {
            delete(account)
            return true
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = url(for: account)
            try Data(value.utf8).write(to: file, options: [.atomic, .completeFileProtection])
            // Solo lectura y escritura para tu usuario (600).
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            return true
        } catch {
            return false
        }
    }

    static func delete(_ account: String) {
        try? FileManager.default.removeItem(at: url(for: account))
    }
}

/// Lectura de la clave antigua del Llavero, solo para trasladarla una vez al archivo.
enum LegacyKeychain {
    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.susurro.Susurro",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
