import Foundation

/// Text plus the audio tokens that speak it.
public struct SpokenText: Hashable, Sendable {
    public let text: String
    public let tokens: [AudioToken]

    public init(text: String, tokens: [AudioToken]) {
        self.text = text
        self.tokens = tokens
    }
}

public enum NumberSpeechError: Error, Equatable, LocalizedError {
    case negative
    case tooLarge(maximum: Int64)

    public var errorDescription: String? {
        switch self {
        case .negative: "Expected a non-negative integer."
        case .tooLarge(let maximum): "Numbers above \(maximum) are not supported."
        }
    }
}

/// Number-to-words converters for Khmer and English.
public enum NumberSpeech {
    /// Largest supported value: 999,999,999,999 (999,999 លាន).
    public static let maximum: Int64 = 999_999_999_999

    /// Converts a non-negative integer into words and audio tokens.
    ///
    /// - Parameter useCompounds: Use pre-recorded round amounts (មួយពាន់, "two hundred thousand", …)
    ///   instead of separate digit and unit clips. Default `true`.
    public static func speak(_ n: Int64, language: SpeechLanguage, useCompounds: Bool = true) throws -> SpokenText {
        let tokens = try self.tokens(n, language: language, useCompounds: useCompounds)
        return SpokenText(text: AudioCatalog.joinText(tokens, language), tokens: tokens)
    }

    public static func tokens(_ n: Int64, language: SpeechLanguage, useCompounds: Bool = true) throws -> [AudioToken] {
        guard n >= 0 else { throw NumberSpeechError.negative }
        guard n <= maximum else { throw NumberSpeechError.tooLarge(maximum: maximum) }
        switch language {
        case .khmer: return khmerTokens(n, useCompounds: useCompounds)
        case .english: return englishTokens(n, useCompounds: useCompounds)
        }
    }

    // MARK: Khmer

    /// Khmer counts with native place-value words, read formally (every place uses its own word):
    /// 1,250,000 → មួយលានពីរសែនប្រាំម៉ឺន. Values ≥ 1,000,000 are "<n> លាន", where <n> is itself a
    /// Khmer number (1,250,000,000 → មួយពាន់ពីររយហាសិបលាន).
    private static func khmerTokens(_ n: Int64, useCompounds: Bool) -> [AudioToken] {
        let num = { (v: Int64) in AudioCatalog.token(.number, String(v), .khmer) }
        let unit = { (v: String) in AudioCatalog.token(.unit, v, .khmer) }
        if n == 0 { return [num(0)] }

        /// 1..99. Digits 6–9 are single recordings (ប្រាំមួយ…), which sound more natural.
        func belowHundred(_ n: Int64) -> [AudioToken] {
            var out: [AudioToken] = []
            if n / 10 > 0 { out.append(num(n / 10 * 10)) }
            if n % 10 > 0 { out.append(num(n % 10)) }
            return out
        }

        /// 1..999,999
        func belowMillion(_ n: Int64) -> [AudioToken] {
            var out: [AudioToken] = []
            let places: [(Int64, String)] = [
                (n / 100_000, "hundred-thousand"), (n / 10_000 % 10, "ten-thousand"),
                (n / 1_000 % 10, "thousand"), (n / 100 % 10, "hundred"),
            ]
            for (digit, name) in places where digit > 0 { out += [num(digit), unit(name)] }
            out += belowHundred(n % 100)
            return out
        }

        var out: [AudioToken] = []
        if n / 1_000_000 > 0 { out += belowMillion(n / 1_000_000) + [unit("million")] }
        if n % 1_000_000 > 0 { out += belowMillion(n % 1_000_000) }
        return useCompounds ? mergeKhmerCompounds(out) : out
    }

    /// Replaces each single-digit number followed by a unit with its compound, when one exists.
    private static func mergeKhmerCompounds(_ tokens: [AudioToken]) -> [AudioToken] {
        var out: [AudioToken] = []
        var i = 0
        while i < tokens.count {
            if i + 1 < tokens.count, tokens[i].type == .number, tokens[i + 1].type == .unit,
               let compound = AudioCatalog.compound(for: [tokens[i], tokens[i + 1]]) {
                out.append(compound)
                i += 2
            } else {
                out.append(tokens[i])
                i += 1
            }
        }
        return out
    }

    // MARK: English

    /// Short scale in groups of three digits: 1,250,000 → "one million two hundred fifty thousand".
    private static func englishTokens(_ n: Int64, useCompounds: Bool) -> [AudioToken] {
        let num = { (v: Int64) in AudioCatalog.token(.number, String(v), .english) }
        let unit = { (v: String) in AudioCatalog.token(.unit, v, .english) }
        if n == 0 { return [num(0)] }

        func maybeCompound(_ parts: [AudioToken], _ allowed: Bool) -> [AudioToken] {
            if allowed, let compound = AudioCatalog.compound(for: parts) { return [compound] }
            return parts
        }

        /// 1..99: 1–19 and the tens are single words; others are "<tens> <ones>".
        func belowHundred(_ n: Int64) -> [AudioToken] {
            if n < 20 { return [num(n)] }
            return n % 10 > 0 ? [num(n - n % 10), num(n % 10)] : [num(n)]
        }

        /// 1..999
        func belowThousand(_ n: Int64, _ compounds: Bool) -> [AudioToken] {
            var out: [AudioToken] = []
            if n / 100 > 0 { out += maybeCompound([num(n / 100), unit("hundred")], compounds) }
            if n % 100 > 0 { out += belowHundred(n % 100) }
            return out
        }

        var out: [AudioToken] = []
        for (scale, name) in [(Int64(1_000_000_000), "billion"), (1_000_000, "million"), (1_000, "thousand")] {
            let group = n / scale % 1000
            if group == 0 { continue }
            // Prefer one compound for the whole group ("two hundred thousand"), else per word.
            let whole = useCompounds ? AudioCatalog.compound(for: belowThousand(group, false) + [unit(name)]) : nil
            out += whole.map { [$0] } ?? (belowThousand(group, useCompounds) + [unit(name)])
        }
        if n % 1000 > 0 { out += belowThousand(n % 1000, useCompounds) }
        return out
    }
}

private let khmerDigits: [Character] = ["០", "១", "២", "៣", "៤", "៥", "៦", "៧", "៨", "៩"]

/// "1,250,000" → "១,២៥០,០០០"
public func toKhmerDigits(_ value: String) -> String {
    String(value.map { ch in ch.wholeNumberValue.flatMap { ch.isASCII ? khmerDigits[$0] : nil } ?? ch })
}
