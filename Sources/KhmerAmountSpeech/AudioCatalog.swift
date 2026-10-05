import Foundation

/// Spoken language of an audio segment.
public enum SpeechLanguage: String, CaseIterable, Sendable {
    case khmer = "km"
    case english = "en"
}

/// Kind of reusable audio segment. The raw value is the folder name inside the resource bundle.
public enum AudioTokenType: String, CaseIterable, Sendable {
    case number = "numbers"
    case unit = "units"
    /// Optional pre-recorded round amount (មួយពាន់, "two hundred thousand", …). Falls back to `parts`.
    case compound = "compounds"
    case currency = "currency"
    case connector = "connectors"
    /// Fixed sentence part placed around the amount (see `VoiceType`).
    case phrase = "phrases"
}

/// One reusable audio segment in a spoken sequence.
public struct AudioToken: Hashable, Sendable, CustomStringConvertible {
    public let language: SpeechLanguage
    public let type: AudioTokenType
    /// Asset value, e.g. "1", "20", "hundred-thousand", "riel", "confirm-prefix".
    public let value: String
    /// Text spoken by this segment.
    public let text: String
    /// Compound tokens only: the separate segments to play if the compound audio is unavailable.
    public let parts: [AudioToken]?

    public init(language: SpeechLanguage, type: AudioTokenType, value: String, text: String, parts: [AudioToken]? = nil) {
        self.language = language
        self.type = type
        self.value = value
        self.text = text
        self.parts = parts
    }

    /// Globally unique id, e.g. "km:compound:1000".
    public var id: String { AudioCatalog.assetId(type, value, language) }

    /// Path of the clip inside the resource bundle, without extension: "audio/km/numbers/1".
    public var resourcePath: String { "audio/\(language.rawValue)/\(type.rawValue)/\(value)" }

    public var description: String { id }
}

/// Catalog entry for one audio file.
public struct AudioAsset: Hashable, Sendable {
    public let language: SpeechLanguage
    public let type: AudioTokenType
    public let value: String
    public let text: String
    /// Romanization to help non-Khmer readers review the asset list.
    public let romanized: String
    /// Common assets are decoded ahead of time by `KhmerAmountSpeaker.preload()`.
    public let preload: Bool

    public var id: String { AudioCatalog.assetId(type, value, language) }
    public var token: AudioToken { AudioToken(language: language, type: type, value: value, text: text) }
}

/// Catalog of every reusable audio segment, per language — the single source of truth for the
/// number formatters and the player. Mirrors `lib/audio-assets.ts` in the web project, so the
/// same recordings work on both platforms.
public enum AudioCatalog {
    private typealias Seed = (value: String, text: String, romanized: String, preload: Bool)
    private typealias PartRef = (type: AudioTokenType, value: String)

    private static func seed(_ value: String, _ text: String, _ romanized: String, preload: Bool = true) -> Seed {
        (value, text, romanized, preload)
    }

    // MARK: Khmer

    private static let kmNumbers: [Seed] = [
        seed("0", "សូន្យ", "soun", preload: false),
        seed("1", "មួយ", "muoy"),
        seed("2", "ពីរ", "pir"),
        seed("3", "បី", "bei"),
        seed("4", "បួន", "buon"),
        seed("5", "ប្រាំ", "pram"),
        seed("6", "ប្រាំមួយ", "pram muoy"),
        seed("7", "ប្រាំពីរ", "pram pir"),
        seed("8", "ប្រាំបី", "pram bei"),
        seed("9", "ប្រាំបួន", "pram buon"),
        seed("10", "ដប់", "dap"),
        seed("20", "ម្ភៃ", "mphey"),
        seed("30", "សាមសិប", "samseb"),
        seed("40", "សែសិប", "saeseb"),
        seed("50", "ហាសិប", "haseb"),
        seed("60", "ហុកសិប", "hokseb"),
        seed("70", "ចិតសិប", "chetseb"),
        seed("80", "ប៉ែតសិប", "paetseb"),
        seed("90", "កៅសិប", "kauseb"),
    ]

    private static let kmUnits: [Seed] = [
        seed("hundred", "រយ", "roy"),
        seed("thousand", "ពាន់", "poan"),
        seed("ten-thousand", "ម៉ឺន", "meun"),
        seed("hundred-thousand", "សែន", "saen"),
        seed("million", "លាន", "lean"),
    ]

    /// "<digit> <unit>" for each unit, e.g. 20000 → ពីរ + ម៉ឺន.
    private static let kmCompounds: [(value: String, parts: [PartRef])] = {
        let units: [(String, Int, Int)] = [
            ("hundred", 100, 9), ("thousand", 1_000, 9), ("ten-thousand", 10_000, 9),
            ("hundred-thousand", 100_000, 9), ("million", 1_000_000, 1),
        ]
        return units.flatMap { unit, multiplier, maxDigit in
            (1...maxDigit).map { d in (String(d * multiplier), [(.number, String(d)), (.unit, unit)]) }
        }
    }()

    private static let kmCurrency: [Seed] = [
        seed("riel", "រៀល", "riel"),
        seed("dollar", "ដុល្លារ", "dollar"),
        seed("cent", "សេន", "sen"),
    ]

    private static let kmConnectors: [Seed] = [seed("and", "និង", "nueng")]

    private static let kmPhrases: [Seed] = [
        seed("confirm-prefix", "ទឹកប្រាក់ចំនួន", "tuek prak chomnuon"),
        seed("confirm-suffix", "សូមផ្ទៀងផ្ទាត់", "som phtieng phtat"),
        seed("received-prefix", "ទទួលប្រាក់ចំនួន", "totuol prak chomnuon"),
    ]

    // MARK: English

    private static let enWords = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
        "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen",
    ]
    private static let enTens = ["twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]

    private static let enNumbers: [Seed] =
        enWords.enumerated().map { seed(String($0.offset), $0.element, $0.element, preload: $0.offset != 0) }
        + enTens.enumerated().map { seed(String(($0.offset + 2) * 10), $0.element, $0.element) }

    private static let enUnits: [Seed] = [
        seed("hundred", "hundred", "hundred"),
        seed("thousand", "thousand", "thousand"),
        seed("million", "million", "million"),
        seed("billion", "billion", "billion", preload: false),
    ]

    /// Same values as the Khmer compounds: one hundred … nine hundred thousand, one million.
    private static let enCompounds: [(value: String, parts: [PartRef])] = {
        var out: [(value: String, parts: [PartRef])] = []
        let hundred: PartRef = (.unit, "hundred")
        let thousand: PartRef = (.unit, "thousand")
        for d in 1...9 { out.append((String(d * 100), [(.number, String(d)), hundred])) }
        for d in 1...9 { out.append((String(d * 1_000), [(.number, String(d)), thousand])) }
        for d in 1...9 { out.append((String(d * 10_000), [(.number, String(d * 10)), thousand])) }
        for d in 1...9 { out.append((String(d * 100_000), [(.number, String(d)), hundred, thousand])) }
        out.append(("1000000", [(.number, "1"), (.unit, "million")]))
        return out
    }()

    private static let enCurrency: [Seed] = [
        seed("riel", "riel", "riel"),
        seed("dollar", "dollar", "dollar"),
        seed("dollars", "dollars", "dollars"),
        seed("cent", "cent", "cent"),
        seed("cents", "cents", "cents"),
    ]

    private static let enPhrases: [Seed] = [
        seed("confirm-prefix", "The amount is", "the amount is"),
        seed("confirm-suffix", "please verify", "please verify"),
        seed("received-prefix", "Received", "received"),
    ]

    // MARK: Catalog

    /// Every asset, Khmer first.
    public static let assets: [AudioAsset] =
        buildLanguage(.khmer, numbers: kmNumbers, units: kmUnits, compounds: kmCompounds,
                      currency: kmCurrency, connectors: kmConnectors, phrases: kmPhrases)
        + buildLanguage(.english, numbers: enNumbers, units: enUnits, compounds: enCompounds,
                        currency: enCurrency, connectors: [], phrases: enPhrases)

    private static let assetsById: [String: AudioAsset] =
        Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })

    /// "km|number:2|unit:thousand" → "2000"
    private static let compoundByParts: [String: String] = {
        var map: [String: String] = [:]
        for (value, parts) in kmCompounds { map[partsKey(.khmer, parts)] = value }
        for (value, parts) in enCompounds { map[partsKey(.english, parts)] = value }
        return map
    }()

    public static func assetId(_ type: AudioTokenType, _ value: String, _ language: SpeechLanguage) -> String {
        "\(language.rawValue):\(typeKey(type)):\(value)"
    }

    public static func asset(_ type: AudioTokenType, _ value: String, _ language: SpeechLanguage) -> AudioAsset? {
        assetsById[assetId(type, value, language)]
    }

    public static func asset(id: String) -> AudioAsset? {
        assetsById[id]
    }

    /// Token for a catalog asset. Crashes on unknown assets, which indicates a programming error.
    public static func token(_ type: AudioTokenType, _ value: String, _ language: SpeechLanguage) -> AudioToken {
        guard let asset = asset(type, value, language) else {
            preconditionFailure("Unknown audio asset \(assetId(type, value, language))")
        }
        return asset.token
    }

    /// The pre-recorded compound that says exactly `parts` (e.g. [ពីរ, ពាន់] → ពីរពាន់), if any.
    public static func compound(for parts: [AudioToken]) -> AudioToken? {
        guard parts.count >= 2, let language = parts.first?.language,
              parts.allSatisfy({ $0.language == language && $0.type != .compound }),
              let value = compoundByParts[partsKey(language, parts.map { ($0.type, $0.value) })]
        else { return nil }
        let base = token(.compound, value, language)
        return AudioToken(language: language, type: .compound, value: value, text: base.text, parts: parts)
    }

    /// Joins segment texts the way each language is written: Khmer without spaces, English with
    /// spaces and hyphenated tens ("twenty-five").
    public static func joinText(_ tokens: [AudioToken], _ language: SpeechLanguage) -> String {
        joinText(tokens.map { ($0.type, $0.value, $0.text) }, language)
    }

    private static func joinText(_ items: [(type: AudioTokenType, value: String, text: String)], _ language: SpeechLanguage) -> String {
        if language == .khmer { return items.map(\.text).joined() }
        var out = ""
        for (i, item) in items.enumerated() {
            if i > 0 {
                let prev = items[i - 1]
                let hyphen = prev.type == .number && (Int(prev.value) ?? 0) >= 20
                    && item.type == .number && (Int(item.value) ?? 99) < 10
                out += hyphen ? "-" : " "
            }
            out += item.text
        }
        return out
    }

    private static func typeKey(_ type: AudioTokenType) -> String {
        switch type {
        case .number: "number"
        case .unit: "unit"
        case .compound: "compound"
        case .currency: "currency"
        case .connector: "connector"
        case .phrase: "phrase"
        }
    }

    private static func partsKey(_ language: SpeechLanguage, _ parts: [PartRef]) -> String {
        ([language.rawValue] + parts.map { "\(typeKey($0.type)):\($0.value)" }).joined(separator: "|")
    }

    private static func buildLanguage(
        _ language: SpeechLanguage,
        numbers: [Seed], units: [Seed], compounds: [(value: String, parts: [PartRef])],
        currency: [Seed], connectors: [Seed], phrases: [Seed]
    ) -> [AudioAsset] {
        func build(_ type: AudioTokenType, _ seeds: [Seed]) -> [AudioAsset] {
            seeds.map { AudioAsset(language: language, type: type, value: $0.value, text: $0.text,
                                   romanized: $0.romanized, preload: $0.preload) }
        }
        let words = build(.number, numbers) + build(.unit, units)
        let compoundSeeds: [Seed] = compounds.map { value, parts in
            let found = parts.map { ref in words.first { $0.type == ref.type && $0.value == ref.value }! }
            let text = joinText(found.map { ($0.type, $0.value, $0.text) }, language)
            return seed(value, text, found.map(\.romanized).joined(separator: " "))
        }
        return words + build(.compound, compoundSeeds) + build(.currency, currency)
            + build(.connector, connectors) + build(.phrase, phrases)
    }
}
