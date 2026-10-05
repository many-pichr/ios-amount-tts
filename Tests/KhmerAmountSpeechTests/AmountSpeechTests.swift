import XCTest
@testable import KhmerAmountSpeech

final class AmountSpeechTests: XCTestCase {
    func testKhmerAmounts() throws {
        let cases: [(String, CurrencyCode, String)] = [
            ("1,250,000", .khr, "មួយលានពីរសែនប្រាំម៉ឺនរៀល"),
            ("1250", .khr, "មួយពាន់ពីររយហាសិបរៀល"),
            ("25.50", .usd, "ម្ភៃប្រាំដុល្លារ ហាសិបសេន"),
            ("12.5", .usd, "ដប់ពីរដុល្លារ ហាសិបសេន"),
            ("0.05", .usd, "ប្រាំសេន"),
            ("10", .usd, "ដប់ដុល្លារ"),
        ]
        for (input, currency, expected) in cases {
            XCTAssertEqual(try AmountSpeech(input, currency: currency).text, expected, input)
        }
    }

    func testEnglishAmounts() throws {
        let cases: [(String, CurrencyCode, String)] = [
            ("1,250,000", .khr, "one million two hundred fifty thousand riel"),
            ("1", .usd, "one dollar"),
            ("1.01", .usd, "one dollar one cent"),
            ("25.50", .usd, "twenty-five dollars fifty cents"),
            ("1,000,000", .usd, "one million dollars"),
        ]
        for (input, currency, expected) in cases {
            XCTAssertEqual(try AmountSpeech(input, currency: currency, language: .english).text, expected, input)
        }
    }

    func testVoiceTypes() throws {
        let confirm = try AmountSpeech("1,000", currency: .khr, voiceType: .confirmPay)
        XCTAssertEqual(confirm.text, "ទឹកប្រាក់ចំនួនមួយពាន់រៀល សូមផ្ទៀងផ្ទាត់")
        XCTAssertEqual(confirm.tokens.map(\.id),
                       ["km:phrase:confirm-prefix", "km:compound:1000", "km:currency:riel", "km:phrase:confirm-suffix"])

        XCTAssertEqual(try AmountSpeech("25.50", currency: .usd, voiceType: .received).text,
                       "ទទួលប្រាក់ចំនួនម្ភៃប្រាំដុល្លារ ហាសិបសេន")
        XCTAssertEqual(try AmountSpeech("1,000", currency: .khr, language: .english, voiceType: .confirmPay).text,
                       "The amount is one thousand riel, please verify")
        XCTAssertEqual(try AmountSpeech("1", currency: .usd, language: .english, voiceType: .received).text,
                       "Received one dollar")
    }

    func testParsing() throws {
        let parsed = try ParsedAmount(" 1,250,000 ", currency: .khr)
        XCTAssertEqual(parsed.major, 1_250_000)
        XCTAssertEqual(parsed.formatted, "1,250,000")
        XCTAssertEqual(try ParsedAmount("25.5", currency: .usd).formatted, "25.50")
        XCTAssertEqual(try ParsedAmount("0012.50", currency: .usd).minor, 50)
        XCTAssertEqual(try ParsedAmount(Decimal(string: "7.25")!, currency: .usd).formatted, "7.25")
    }

    func testParsingErrors() {
        let errors: [(String, CurrencyCode, AmountError)] = [
            ("", .khr, .empty),
            ("abc", .khr, .invalidFormat),
            ("1,25,000", .khr, .invalidFormat),
            ("-5", .khr, .negative),
            ("10.5", .khr, .tooManyDecimals(currency: .khr)),
            ("1.234", .usd, .tooManyDecimals(currency: .usd)),
            ("1,000,000,000,000", .khr, .tooLarge),
        ]
        for (input, currency, expected) in errors {
            XCTAssertThrowsError(try ParsedAmount(input, currency: currency), input) { error in
                XCTAssertEqual(error as? AmountError, expected, input)
            }
        }
    }
}
