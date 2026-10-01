import Foundation
import UserNotifications

struct AppError: LocalizedError {
    /// Where the user can fix the problem: the settings window (permissions) or the keys file.
    enum Fix { case none, settings, keys }

    let message: String
    let fix: Fix

    init(_ message: String, fix: Fix = .none) {
        self.message = message
        self.fix = fix
    }

    var errorDescription: String? { message }

    /// Turns any error into a short message for the user.
    static func from(_ error: Error) -> AppError {
        if let error = error as? AppError { return error }
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff:
                return AppError("Sem conexão com a internet.")
            case .timedOut:
                return AppError("A conexão demorou demais. Tente de novo.")
            default: break
            }
        }
        return AppError(error.localizedDescription)
    }

    static func http(status: Int, provider: Provider, body: Data) -> AppError {
        let name = provider.name
        switch status {
        case 401, 403:
            return AppError(
                "\(name): a chave foi recusada. Confira \(provider.keyName) no arquivo de chaves.", fix: .keys)
        case 429:
            return AppError("\(name): limite de pedidos atingido. Aguarde um minuto e tente de novo.")
        case 413:
            return AppError("\(name): o áudio é grande demais.")
        case 500...599:
            return AppError("\(name): o serviço está com problema. Tente de novo mais tarde.")
        default:
            let detail = apiMessage(body)
            return AppError("\(name): pedido recusado (erro \(status)).\(detail.isEmpty ? "" : " \(detail)")")
        }
    }

    private static func apiMessage(_ data: Data) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = root["error"] as? [String: Any],
            let message = error["message"] as? String
        else { return "" }
        return String(message.prefix(160))
    }
}

enum Provider {
    case google, anthropic
    var name: String { self == .google ? "Google" : "Anthropic" }
    var keyName: String { self == .google ? "GOOGLE_API_KEY" : "ANTHROPIC_API_KEY" }
}

enum Config {
    /// Recorded time, pauses excluded.
    static let maxRecordingSeconds: TimeInterval = 30 * 60
    static let pauseReminderSeconds: TimeInterval = 10 * 60
    /// Transcripts with fewer words than this are not worth a minutes request (silence, a stray syllable).
    static let minWords = 10
    static let defaultTranscriber = "gemini"
    static let defaultTranscriberModel = "gemini-3.5-transcribe"
    static let defaultMinuter = "claude"
    static let defaultMinuterModel = "claude-sonnet-5-5"
    static let userNameKey = "userName"
    static let outputDirKey = "outputDir"

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

enum AppVersion {
    /// Version, build number (commit count) and commit that `scripts/build-app.sh` stamped into Info.plist.
    static var text: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        var text = "Versão \(version) · build \(build)"
        if let commit = info["MinutaCommit"] as? String { text += " · \(commit)" }
        return text
    }
}

enum Notifier {
    /// Asks for permission the first time a notification is about to appear, not at launch.
    /// The system shows the prompt once; later calls only read the saved answer.
    static func post(_ title: String, _ body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}

enum Fmt {
    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    /// Elapsed recording time as mm:ss, or h:mm:ss from one hour.
    static func elapsed(_ seconds: Double) -> String {
        let s = Int(seconds)
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// "dd/MM/yyyy HH:mm", for lists.
    static func listDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "dd/MM/yyyy HH:mm"
        return f.string(from: date)
    }

    /// "13 s" under a minute, "28 min" from there.
    static func shortDuration(_ seconds: Double) -> String {
        seconds < 60 ? "\(Int(seconds)) s" : "\(Int((seconds / 60).rounded())) min"
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

func httpCheck(_ response: URLResponse, _ data: Data, provider: Provider) throws {
    guard let http = response as? HTTPURLResponse else {
        throw AppError("\(provider.name): resposta inválida.")
    }
    guard (200..<300).contains(http.statusCode) else {
        throw AppError.http(status: http.statusCode, provider: provider, body: data)
    }
}
