import Foundation

/// Cleans the transcript with the LLM after `TranscriptBuilder` (ADR 0031). The model only proposes new text per
/// segment; `apply` decides what is used, so a bad answer never changes what was said. Any failure leaves the
/// transcript as the speech-to-text returned it.
enum TranscriptCleaner {
    /// Words per request, so the answer of a long meeting fits in one response.
    static let chunkWords = 2500

    static func clean(_ transcript: Transcript) async -> Transcript {
        guard let minuter = try? Providers.minuter() else { return transcript }
        var cleaned: [String: String] = [:]
        await withTaskGroup(of: [String: String].self) { group in
            for chunk in chunks(transcript.segments) {
                group.addTask { (try? await minuter.clean(segments: chunk)) ?? [:] }
            }
            for await part in group { cleaned.merge(part) { first, _ in first } }
        }
        return apply(cleaned, to: transcript)
    }

    static func chunks(_ segments: [Segment]) -> [[Segment]] {
        var result: [[Segment]] = []
        var current: [Segment] = []
        var words = 0
        for segment in segments {
            let count = tokens(segment.text).count
            if words + count > chunkWords, !current.isEmpty {
                result.append(current)
                current = []
                words = 0
            }
            current.append(segment)
            words += count
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Uses the cleaned text of a segment only when it is a safe edit of the original: the same words minus some,
    /// and not most of the segment gone. A segment of three words or fewer that comes back empty is dropped.
    static func apply(_ cleaned: [String: String], to transcript: Transcript) -> Transcript {
        var segments: [Segment] = []
        for segment in transcript.segments {
            guard let proposal = cleaned[segment.id] else {
                segments.append(segment)
                continue
            }
            let text = proposal.trimmingCharacters(in: .whitespacesAndNewlines)
            let before = tokens(segment.text)
            let after = tokens(text)
            if after.isEmpty {
                if before.count > 3 { segments.append(segment) }
                continue
            }
            guard isSubset(after, of: before), before.count < 8 || after.count * 2 >= before.count,
                text != segment.text
            else {
                segments.append(segment)
                continue
            }
            var edited = segment
            edited.text = text
            edited.raw = segment.raw ?? segment.text
            segments.append(edited)
        }
        return Transcript(segments: segments)
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func isSubset(_ small: [String], of large: [String]) -> Bool {
        var available: [String: Int] = [:]
        for word in large { available[word, default: 0] += 1 }
        for word in small {
            guard let left = available[word], left > 0 else { return false }
            available[word] = left - 1
        }
        return true
    }
}
