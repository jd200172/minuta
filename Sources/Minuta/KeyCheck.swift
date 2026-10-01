import Foundation

/// Checks an API key with a cheap, read-only request. Returns nil when the key works.
enum KeyCheck {
    static func google(_ key: String) async -> AppError? {
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1")!)
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        return await run(request, provider: .google)
    }

    static func anthropic(_ key: String) async -> AppError? {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=1")!)
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        return await run(request, provider: .anthropic)
    }

    private static func run(_ request: URLRequest, provider: Provider) async -> AppError? {
        var request = request
        request.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return AppError("\(provider.name): resposta inválida.") }
            if (200..<300).contains(http.statusCode) { return nil }
            // Google answers an invalid key with 400 and "API key not valid".
            let body = String(data: data, encoding: .utf8) ?? ""
            let status = (http.statusCode == 400 && body.contains("API key not valid")) ? 401 : http.statusCode
            return AppError.http(status: status, provider: provider, body: data)
        } catch {
            return AppError.from(error)
        }
    }
}
