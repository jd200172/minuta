import Foundation
import Security
import UserNotifications

struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum Config {
    static let maxRecordingSeconds: TimeInterval = 30 * 60
    static let geminiModel = "gemini-3.5-transcribe"
    static let claudeModel = "claude-sonnet-5-5"
    static let userNameKey = "userName"
    static let outputDirKey = "outputDir"
    static let googleAccount = "google-api-key"
    static let anthropicAccount = "anthropic-api-key"

    static var userName: String {
        let name = UserDefaults.standard.string(forKey: userNameKey) ?? ""
        return name.trimmingCharacters(in: .whitespaces).isEmpty ? "Eu" : name
    }

    /// Set by the developer CLI mode so it never touches the user's saved folder.
    nonisolated(unsafe) static var outputOverride: URL?

    static var outputDir: URL {
        if let outputOverride { return outputOverride }
        let path = UserDefaults.standard.string(forKey: outputDirKey) ?? ""
        if !path.isEmpty { return URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Atas")
    }
}

enum Keychain {
    private static let service = "app.minuta.Minuta"

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    static func post(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

enum Fmt {
    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    static func jobID(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }

    static func fileStem(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HHmm"
        return f.string(from: date)
    }

    static func meetingDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "EEEE, dd/MM/yyyy"
        return f.string(from: date)
    }

    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        return f.string(from: date)
    }
}

func httpCheck(_ response: URLResponse, _ data: Data, service: String) throws {
    guard let http = response as? HTTPURLResponse else { throw AppError("\(service): resposta inválida.") }
    guard (200..<300).contains(http.statusCode) else {
        let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
        throw AppError("\(service): erro \(http.statusCode). \(body)")
    }
}
