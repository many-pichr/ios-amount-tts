import Foundation

/// Supported currencies.
public enum CurrencyCode: String, CaseIterable, Sendable {
    case khr = "KHR"
    case usd = "USD"

    public var symbol: String {
        switch self {
        case .khr: "៛"
        case .usd: "$"
        }
    }

    /// Maximum number of fraction digits accepted in input.
    public var decimals: Int {
        switch self {
        case .khr: 0
        case .usd: 2
        }
    }

    /// Catalog value (type `.currency`) for the major unit.
    var majorUnit: String {
        switch self {
        case .khr: "riel"
        case .usd: "dollar"
        }
    }

    /// Catalog value for the spoken minor unit, if any.
    var minorUnit: String? {
        switch self {
        case .khr: nil
        case .usd: "cent"
        }
    }
}

/// Phrases spoken around the amount.
///
/// | Voice type    | Khmer                                  | English                                 |
/// | ------------- | -------------------------------------- | --------------------------------------- |
/// | `.amount`     | {{amount}}                             | {{amount}}                              |
/// | `.confirmPay` | ទឹកប្រាក់ចំនួន{{amount}} សូមផ្ទៀងផ្ទាត់   | The amount is {{amount}}, please verify |
/// | `.received`   | ទទួលប្រាក់ចំនួន{{amount}}                | Received {{amount}}                     |
public enum VoiceType: String, CaseIterable, Sendable {
    case amount
    case confirmPay = "confirm-pay"
    case received

    var prefix: String? {
        switch self {
        case .amount: nil
        case .confirmPay: "confirm-prefix"
        case .received: "received-prefix"
        }
    }

    var suffix: String? {
        self == .confirmPay ? "confirm-suffix" : nil
    }
}

public enum AmountError: Error, Equatable, LocalizedError {
    case empty
    case invalidFormat
    case negative
    case tooManyDecimals(currency: CurrencyCode)
    case tooLarge

    public var errorDescription: String? {
        switch self {
        case .empty: "Please enter an amount."
        case .invalidFormat: "Please enter a valid number, for example 1,250,000 or 25.50."
        case .negative: "The amount cannot be negative."
        case .tooManyDecimals(let currency):
            currency.decimals == 0
                ? "\(currency.rawValue) amounts must be whole numbers (no decimal places)."
                : "\(currency.rawValue) amounts allow at most \(currency.decimals) decimal places."
        case .tooLarge: "The amount is too large. The maximum is 999,999,999,999."
        }
    }
}

/// A validated amount.
public struct ParsedAmount: Hashable, Sendable {
    public let currency: CurrencyCode
    /// Whole major units (riel / dollars).
    public let major: Int64
    /// Minor units (cents), 0 when the currency has none.
    public let minor: Int64
    /// Canonical display string, e.g. "1,250,000" or "25.50".
    public let formatted: String

    /// Parses user input such as "1,250,000", "25.5" or " 12.50 ". Parsing is entirely local.
    public init(_ input: String, currency: CurrencyCode) throws {
        let raw = input.filter { !$0.isWhitespace }
        guard !raw.isEmpty else { throw AmountError.empty }
        guard !raw.hasPrefix("-"), !raw.hasPrefix("−") else { throw AmountError.negative }

        let plain = #"^(\d+)(?:\.(\d+))?$"#
        let grouped = #"^(\d{1,3}(?:,\d{3})+)(?:\.(\d+))?$"#
        guard let match = Self.match(raw, plain) ?? Self.match(raw, grouped) else { throw AmountError.invalidFormat }

        var integerDigits = match.integer.replacingOccurrences(of: ",", with: "")
        while integerDigits.count > 1, integerDigits.hasPrefix("0") { integerDigits.removeFirst() }
        var fractionDigits = match.fraction
        while fractionDigits.hasSuffix("0") { fractionDigits.removeLast() }

        guard fractionDigits.count <= currency.decimals else { throw AmountError.tooManyDecimals(currency: currency) }
        guard integerDigits.count <= 12, let major = Int64(integerDigits), major <= NumberSpeech.maximum else {
            throw AmountError.tooLarge
        }

        self.currency = currency
        self.major = major
        self.minor = currency.decimals > 0
            ? Int64(fractionDigits.padding(toLength: currency.decimals, withPad: "0", startingAt: 0)) ?? 0
            : 0

        let grouping = NumberFormatter()
        grouping.locale = Locale(identifier: "en_US_POSIX")
        grouping.numberStyle = .decimal
        grouping.usesGroupingSeparator = true
        grouping.groupingSeparator = ","
        grouping.groupingSize = 3
        let integerText = grouping.string(from: NSNumber(value: major)) ?? String(major)
        self.formatted = currency.decimals > 0
            ? integerText + "." + String(format: "%0\(currency.decimals)lld", minor)
            : integerText
    }

    public init(_ value: Decimal, currency: CurrencyCode) throws {
        try self.init(NSDecimalNumber(decimal: value).stringValue, currency: currency)
    }

    private static func match(_ text: String, _ pattern: String) -> (integer: String, fraction: String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let integer = Range(m.range(at: 1), in: text)
        else { return nil }
        let fraction = Range(m.range(at: 2), in: text).map { String(text[$0]) } ?? ""
        return (String(text[integer]), fraction)
    }
}

/// An amount converted into text and the audio tokens that speak it.
public struct AmountSpeech: Hashable, Sendable {
    public let text: String
    public let tokens: [AudioToken]
    public let amount: ParsedAmount
    public let language: SpeechLanguage
    public let voiceType: VoiceType

    /// Converts an amount into text and audio tokens.
    ///
    ///     try AmountSpeech("1,250,000", currency: .khr).text
    ///     // "មួយលានពីរសែនប្រាំម៉ឺនរៀល"
    ///     try AmountSpeech("25.50", currency: .usd, language: .english).text
    ///     // "twenty-five dollars fifty cents"
    ///     try AmountSpeech("1,000", currency: .khr, voiceType: .received).text
    ///     // "ទទួលប្រាក់ចំនួនមួយពាន់រៀល"
    public init(
        _ input: String,
        currency: CurrencyCode,
        language: SpeechLanguage = .khmer,
        voiceType: VoiceType = .amount,
        useCompounds: Bool = true
    ) throws {
        try self.init(ParsedAmount(input, currency: currency), language: language, voiceType: voiceType,
                      useCompounds: useCompounds)
    }

    public init(
        _ amount: ParsedAmount,
        language: SpeechLanguage = .khmer,
        voiceType: VoiceType = .amount,
        useCompounds: Bool = true
    ) throws {
        let currency = amount.currency
        func words(_ n: Int64) throws -> [AudioToken] {
            try NumberSpeech.tokens(n, language: language, useCompounds: useCompounds)
        }
        /// English currency words take a plural form unless the count is 1; riel does not change.
        func currencyToken(_ value: String, count: Int64) -> AudioToken {
            if language == .english, count != 1, AudioCatalog.asset(.currency, value + "s", language) != nil {
                return AudioCatalog.token(.currency, value + "s", language)
            }
            return AudioCatalog.token(.currency, value, language)
        }
        let join = { (tokens: [AudioToken]) in AudioCatalog.joinText(tokens, language) }

        let majorTokens = try words(amount.major) + [currencyToken(currency.majorUnit, count: amount.major)]
        var spokenText: String
        var spokenTokens: [AudioToken]
        if let minorUnit = currency.minorUnit, amount.minor > 0 {
            let minorTokens = try words(amount.minor) + [currencyToken(minorUnit, count: amount.minor)]
            if amount.major == 0 {
                (spokenText, spokenTokens) = (join(minorTokens), minorTokens)
            } else {
                (spokenText, spokenTokens) = ("\(join(majorTokens)) \(join(minorTokens))", majorTokens + minorTokens)
            }
        } else {
            (spokenText, spokenTokens) = (join(majorTokens), majorTokens)
        }

        let before = voiceType.prefix.map { AudioCatalog.token(.phrase, $0, language) }
        let after = voiceType.suffix.map { AudioCatalog.token(.phrase, $0, language) }
        // Khmer is written without a space after the prefix; English separates words (and the
        // suffix with a comma).
        switch language {
        case .khmer:
            spokenText = (before?.text ?? "") + spokenText + (after.map { " \($0.text)" } ?? "")
        case .english:
            spokenText = (before.map { "\($0.text) " } ?? "") + spokenText + (after.map { ", \($0.text)" } ?? "")
        }
        spokenTokens = (before.map { [$0] } ?? []) + spokenTokens + (after.map { [$0] } ?? [])

        self.text = spokenText
        self.tokens = spokenTokens
        self.amount = amount
        self.language = language
        self.voiceType = voiceType
    }
}
