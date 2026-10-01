import AppKit
import Security

/// API keys and provider choices live in a plain `.env` file, read again on every use:
/// `~/Library/Application Support/Minuta/.env` (ADR 0012).
enum Env {
    static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Minuta/.env")
    }

    static func value(_ name: String) -> String? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let value = parse(text)[name] ?? ""
        return value.isEmpty ? nil : value
    }

    static func key(_ provider: Provider) throws -> String {
        guard let key = value(provider.keyName) else {
            throw AppError("Defina \(provider.keyName) no arquivo de chaves.", fix: .keys)
        }
        return key
    }

    /// Opens the file in TextEdit, creating it first when missing.
    @MainActor static func open() {
        prepare()
        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open([file], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
    }

    /// KEY=VALUE per line. Blank lines and `#` comments are skipped; `export ` and quotes are optional.
    static func parse(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)) }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let name = line[..<equals].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
                value = String(value.dropFirst().dropLast())
            }
            values[name] = value
        }
        return values
    }

    static func template(google: String = "", anthropic: String = "") -> String {
        """
        # Chaves e modelos do minuta. O app lê este arquivo a cada uso: salve e pronto.
        # Mantenha só neste Mac. Não compartilhe nem versione.

        GOOGLE_API_KEY=\(google)
        ANTHROPIC_API_KEY=\(anthropic)

        # Provedor e modelo de cada etapa. Provedores aceitos hoje:
        # TRANSCRIBER: gemini    MINUTER: claude
        TRANSCRIBER=\(Config.defaultTranscriber)
        TRANSCRIBER_MODEL=\(Config.defaultTranscriberModel)
        MINUTER=\(Config.defaultMinuter)
        MINUTER_MODEL=\(Config.defaultMinuterModel)

        """
    }

    /// Creates the file when missing, carrying over keys that earlier versions kept in the Keychain.
    static func prepare() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: file.path) else { return }
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let google = LegacyKeychain.get("google-api-key") ?? ""
        let anthropic = LegacyKeychain.get("anthropic-api-key") ?? ""
        let text = template(google: google, anthropic: anthropic)
        guard
            fm.createFile(
                atPath: file.path, contents: Data(text.utf8),
                attributes: [.posixPermissions: 0o600])
        else { return }
        // Only remove the Keychain items once the file holds their values.
        if !google.isEmpty { LegacyKeychain.remove("google-api-key") }
        if !anthropic.isEmpty { LegacyKeychain.remove("anthropic-api-key") }
    }
}

/// Reads and removes the items that versions before ADR 0012 saved in the Keychain.
private enum LegacyKeychain {
    private static let service = "app.minuta.Minuta.keys"

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func get(_ account: String) -> String? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
