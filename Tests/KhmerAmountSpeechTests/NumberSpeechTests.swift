import XCTest
@testable import KhmerAmountSpeech

final class NumberSpeechTests: XCTestCase {
    private func khmer(_ n: Int64) throws -> String { try NumberSpeech.speak(n, language: .khmer).text }
    private func english(_ n: Int64) throws -> String { try NumberSpeech.speak(n, language: .english).text }
    private func ids(_ n: Int64, _ language: SpeechLanguage, compounds: Bool = true) throws -> [String] {
        try NumberSpeech.tokens(n, language: language, useCompounds: compounds).map { "\($0.type):\($0.value)" }
    }

    func testKhmerFormalReading() throws {
        let cases: [(Int64, String)] = [
            (0, "សូន្យ"), (1, "មួយ"), (6, "ប្រាំមួយ"), (11, "ដប់មួយ"), (25, "ម្ភៃប្រាំ"), (99, "កៅសិបប្រាំបួន"),
            (100, "មួយរយ"), (101, "មួយរយមួយ"), (1_000, "មួយពាន់"), (1_250, "មួយពាន់ពីររយហាសិប"),
            (10_000, "មួយម៉ឺន"), (25_500, "ពីរម៉ឺនប្រាំពាន់ប្រាំរយ"), (125_000, "មួយសែនពីរម៉ឺនប្រាំពាន់"),
            (999_999, "ប្រាំបួនសែនប្រាំបួនម៉ឺនប្រាំបួនពាន់ប្រាំបួនរយកៅសិបប្រាំបួន"), (1_000_000, "មួយលាន"),
            (1_250_000, "មួយលានពីរសែនប្រាំម៉ឺន"), (10_500_000, "ដប់លានប្រាំសែន"), (100_000_000, "មួយរយលាន"),
            (1_250_000_000, "មួយពាន់ពីររយហាសិបលាន"),
        ]
        for (n, expected) in cases { XCTAssertEqual(try khmer(n), expected, "\(n)") }
    }

    func testKhmerCompounds() throws {
        for d: Int64 in 1...9 {
            for value in [d * 100, d * 1_000, d * 10_000, d * 100_000] {
                XCTAssertEqual(try ids(value, .khmer), ["compound:\(value)"])
            }
        }
        XCTAssertEqual(try ids(1_000_000, .khmer), ["compound:1000000"])
        XCTAssertEqual(try ids(1_250_000, .khmer), ["compound:1000000", "compound:200000", "compound:50000"])
        XCTAssertEqual(try ids(20_000_000, .khmer), ["number:20", "unit:million"])
        XCTAssertEqual(try ids(1_250_000, .khmer, compounds: false),
                       ["number:1", "unit:million", "number:2", "unit:hundred-thousand", "number:5", "unit:ten-thousand"])
        let compound = try NumberSpeech.tokens(3_000, language: .khmer)[0]
        XCTAssertEqual(compound.parts?.map(\.value), ["3", "thousand"])
    }

    func testEnglishReading() throws {
        let cases: [(Int64, String)] = [
            (0, "zero"), (13, "thirteen"), (25, "twenty-five"), (101, "one hundred one"),
            (1_250, "one thousand two hundred fifty"), (15_000, "fifteen thousand"),
            (125_000, "one hundred twenty-five thousand"), (1_250_000, "one million two hundred fifty thousand"),
            (1_250_000_000, "one billion two hundred fifty million"),
        ]
        for (n, expected) in cases { XCTAssertEqual(try english(n), expected, "\(n)") }
    }

    func testEnglishCompounds() throws {
        for d: Int64 in 1...9 {
            for value in [d * 100, d * 1_000, d * 10_000, d * 100_000] {
                XCTAssertEqual(try ids(value, .english), ["compound:\(value)"])
            }
        }
        XCTAssertEqual(try ids(1_250_000, .english), ["compound:1000000", "compound:200", "number:50", "unit:thousand"])
        XCTAssertEqual(try ids(200_000, .english, compounds: false), ["number:2", "unit:hundred", "unit:thousand"])
    }

    func testTextIsConcatenationOfTokens() throws {
        for n: Int64 in [0, 7, 1_001, 25_500, 1_250_000, 999_999_999_999] {
            let spoken = try NumberSpeech.speak(n, language: .khmer)
            XCTAssertEqual(spoken.tokens.map(\.text).joined(), spoken.text)
        }
    }

    func testRange() {
        XCTAssertThrowsError(try NumberSpeech.speak(-1, language: .khmer))
        XCTAssertThrowsError(try NumberSpeech.speak(NumberSpeech.maximum + 1, language: .english))
        XCTAssertNoThrow(try NumberSpeech.speak(NumberSpeech.maximum, language: .khmer))
    }

    func testKhmerDigits() {
        XCTAssertEqual(toKhmerDigits("1,250,000"), "១,២៥០,០០០")
    }
}
