import Foundation

/// One timed subtitle cue.
struct SubtitleCue: Identifiable, Equatable {
    let id = UUID()
    let start: TimeInterval
    let end: TimeInterval
    let text: String

    func contains(_ t: TimeInterval) -> Bool { t >= start && t < end }
}

/// Parses SubRip (.srt) and WebVTT (.vtt) into a sorted list of cues.
///
/// Tolerant by design: handles CRLF/LF, a leading BOM, the `WEBVTT` header,
/// numeric SRT indices, `,`/`.` millisecond separators, and strips inline
/// markup (`<i>`, `{\an8}`, etc.) so cues render as plain text.
enum SubtitleParser {
    static func parse(_ raw: String) -> [SubtitleCue] {
        var text = raw
        // Drop a UTF-8 BOM if present.
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        // Normalise line endings.
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
                   .replacingOccurrences(of: "\r", with: "\n")

        var cues: [SubtitleCue] = []
        // Blocks are separated by one or more blank lines.
        let blocks = text.components(separatedBy: "\n\n")
        for block in blocks {
            var lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard !lines.isEmpty else { continue }
            // Skip a "WEBVTT" header block.
            if lines[0].uppercased().hasPrefix("WEBVTT") { continue }
            // SRT blocks start with a numeric index line — drop it.
            if let first = lines.first, Int(first.trimmingCharacters(in: .whitespaces)) != nil {
                lines.removeFirst()
            }
            guard let timing = lines.first, timing.contains("-->") else { continue }
            guard let (start, end) = parseTiming(timing) else { continue }

            let body = lines.dropFirst()
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let clean = strip(body)
            guard !clean.isEmpty else { continue }
            cues.append(SubtitleCue(start: start, end: end, text: clean))
        }
        return cues.sorted { $0.start < $1.start }
    }

    // MARK: Timing

    /// Parses "00:00:01,000 --> 00:00:04,000" (optional VTT cue settings ignored).
    private static func parseTiming(_ line: String) -> (TimeInterval, TimeInterval)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }
        guard let start = seconds(from: parts[0]) else { return nil }
        // The end side may carry VTT positioning ("... line:90% align:middle").
        let endToken = parts[1].trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces).first ?? parts[1]
        guard let end = seconds(from: endToken) else { return nil }
        return (start, end)
    }

    /// "HH:MM:SS,mmm" / "MM:SS.mmm" → seconds.
    private static func seconds(from token: String) -> TimeInterval? {
        let t = token.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        let segments = t.components(separatedBy: ":")
        guard (1...3).contains(segments.count) else { return nil }
        var total: TimeInterval = 0
        for seg in segments {
            guard let value = Double(seg) else { return nil }
            total = total * 60 + value
        }
        return total
    }

    // MARK: Markup

    /// Removes SRT/VTT inline markup so cues are clean display text.
    private static func strip(_ s: String) -> String {
        var out = s
        // HTML-ish tags: <i>, </font>, <c.color> …
        out = out.replacingOccurrences(of: "<[^>]+>", with: "",
                                       options: .regularExpression)
        // SSA/ASS overrides: {\an8}, {\pos(...)} …
        out = out.replacingOccurrences(of: "\\{[^}]*\\}", with: "",
                                       options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
