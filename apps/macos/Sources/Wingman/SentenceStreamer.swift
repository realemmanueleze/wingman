import Foundation

/// Turns a streaming token feed into speakable sentences so TTS can start
/// on the first sentence instead of waiting for the full reply.
///
/// Emission stops at any `[POINT` occurrence: the point tag is a trailing
/// machine directive that must never be spoken, so everything from its start
/// onward stays buffered for the caller to strip at end of turn.
@MainActor
final class SentenceStreamer {
    private var buffer = ""
    private(set) var emittedAny = false

    private static let terminators: Set<Character> = [".", "!", "?", "…"]

    /// Feed a delta; returns any newly completed sentences.
    func ingest(_ delta: String) -> [String] {
        buffer += delta
        var sentences: [String] = []
        while let boundary = nextBoundary() {
            let sentence = String(buffer[..<boundary])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeSubrange(buffer.startIndex..<boundary)
            if !sentence.isEmpty {
                sentences.append(sentence)
                emittedAny = true
            }
        }
        return sentences
    }

    /// Remaining unemitted text (may still contain a point tag).
    func flush() -> String {
        let rest = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return rest
    }

    /// Index just past the next sentence end, or nil if no complete sentence
    /// is buffered yet. A terminator only counts when followed by whitespace,
    /// so decimals like "3.14" don't split.
    private func nextBoundary() -> String.Index? {
        let searchEnd = buffer.range(of: "[POINT")?.lowerBound ?? buffer.endIndex
        var index = buffer.startIndex
        while index < searchEnd {
            let character = buffer[index]
            if character == "\n" {
                return buffer.index(after: index)
            }
            if Self.terminators.contains(character) {
                let next = buffer.index(after: index)
                if next < searchEnd, buffer[next].isWhitespace {
                    return next
                }
            }
            index = buffer.index(after: index)
        }
        return nil
    }
}
