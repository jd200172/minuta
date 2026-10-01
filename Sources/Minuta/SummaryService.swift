import Foundation

extension Notification.Name {
    /// Posted with the ata's file URL as `object` whenever its `.md` was rewritten by a summary change.
    static let ataChanged = Notification.Name("MinutaAtaChanged")
}

/// Generates, reuses and switches the summaries of a meeting (ADR 0017). A model that already has a summary
/// is shown from the sidecar without calling the LLM; a missing one is generated once and kept.
@MainActor
final class SummaryService: ObservableObject {
    static let shared = SummaryService()

    /// The model being generated, by ata.
    @Published private(set) var running: [URL: SummaryModel] = [:]

    /// Makes `model` the summary of the ata at `url`. With `force`, generates it again even if it exists.
    func show(_ model: SummaryModel, for url: URL, force: Bool = false) async throws {
        guard running[url] == nil else { throw AppError("Já há um resumo sendo gerado para esta reunião.") }
        let text = try String(contentsOf: url, encoding: .utf8)
        let (sidecar, _) = try AtaStore.loadSidecar(for: url, text: text)
        if sidecar.has(model), !force {
            try AtaStore.select(model, in: url)
            changed(url)
            return
        }
        running[url] = model
        defer { running[url] = nil }
        let minuter = try Providers.minuter()
        let names = ParticipantEditor.names(in: text)
        let start = ISO8601DateFormatter().date(from: sidecar.inicio) ?? Date()
        let data = try await minuter.summarize(
            model: model, transcript: Transcript(segments: sidecar.segments), start: start, names: names)
        try AtaStore.commit(data, model: model, to: url)
        changed(url)
    }

    private func changed(_ url: URL) {
        // The developer CLI writes to its own folder and must not touch the list or the saved folder.
        if Config.outputOverride == nil { AtaLibrary.shared.refresh() }
        NotificationCenter.default.post(name: .ataChanged, object: url)
    }
}
