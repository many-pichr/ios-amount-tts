import AVFoundation
import XCTest
@testable import KhmerAmountSpeech

final class ExporterTests: XCTestCase {
    private func uint32(_ data: Data, _ offset: Int) -> UInt32 {
        data.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
    }

    private func uint16(_ data: Data, _ offset: Int) -> UInt16 {
        data.subdata(in: offset..<offset + 2).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }.littleEndian
    }

    func testEncoderHeaderPCM16() {
        let data = WAVEncoder.encode([0, 0.5, -1, 2], sampleRate: 44_100)
        XCTAssertEqual(String(decoding: data[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(uint16(data, 20), 1)          // PCM
        XCTAssertEqual(uint16(data, 22), 1)          // mono
        XCTAssertEqual(uint32(data, 24), 44_100)
        XCTAssertEqual(uint16(data, 34), 16)
        XCTAssertEqual(uint32(data, 40), 8)          // 4 samples × 2 bytes
        XCTAssertEqual(data.count, 44 + 8)
        XCTAssertEqual(uint32(data, 4), UInt32(data.count - 8))
        // 2 is clipped to full scale.
        XCTAssertEqual(Int16(bitPattern: uint16(data, 50)), Int16.max)
    }

    func testEncoderFloat32() {
        let data = WAVEncoder.encode([0.25], sampleRate: 44_100, format: .float32)
        XCTAssertEqual(uint16(data, 20), 3)          // IEEE float
        XCTAssertEqual(uint16(data, 34), 32)
        XCTAssertEqual(Float(bitPattern: uint32(data, 44)), 0.25)
    }

    func testExportsAmountAsReadableWAV() async throws {
        let exporter = AmountAudioExporter()
        let speech = try AmountSpeech("50,000", currency: .khr, voiceType: .received)
        let sequence = try await exporter.renderSequence(speech.tokens)
        XCTAssertEqual(Set(sequence.segments.map(\.tokenIndex)), [0, 1, 2])

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("amount-\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try await exporter.writeWAV(for: speech, to: url)

        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.fileFormat.sampleRate, 44_100)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        XCTAssertEqual(file.length, AVAudioFramePosition(sequence.samples.count))
        XCTAssertGreaterThan(sequence.duration, 1)   // ទទួលប្រាក់ចំនួន + ប្រាំម៉ឺន + រៀល
        XCTAssertLessThan(sequence.duration, 6)
    }

    func testSpeechWAVReturnsFileURL() async throws {
        let exporter = AmountAudioExporter()
        let url = try await exporter.speechWAV("50,000", currency: .khr, voiceType: .received)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.pathExtension, "wav")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL,
                       AmountAudioExporter.defaultDirectory.standardizedFileURL)
        let expected = try await exporter.wavData("50,000", currency: .khr, voiceType: .received)
        XCTAssertEqual(try Data(contentsOf: url), expected)

        // A second call gets its own file.
        let other = try await exporter.speechWAV("50,000", currency: .khr, voiceType: .received)
        defer { try? FileManager.default.removeItem(at: other) }
        XCTAssertNotEqual(url, other)
    }

    func testSpeechWAVCustomDirectoryAndName() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID())/nested")
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let speech = try AmountSpeech("25.50", currency: .usd, language: .english)

        let url = try await AmountAudioExporter().speechWAV(for: speech, directory: folder, fileName: "order-42")
        XCTAssertEqual(url.lastPathComponent, "order-42.wav")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let same = try await AmountAudioExporter().speechWAV(for: speech, directory: folder, fileName: "order-42.wav")
        XCTAssertEqual(same, url)
    }

    func testInputConvenienceMatchesSpeech() async throws {
        let exporter = AmountAudioExporter()
        let a = try await exporter.wavData("25.50", currency: .usd, language: .english)
        let b = try await exporter.wavData(for: AmountSpeech("25.50", currency: .usd, language: .english))
        XCTAssertEqual(a, b)
    }

    func testMissingAudioFailsByDefault() async {
        let exporter = AmountAudioExporter(resolveURL: { _ in nil })
        do {
            _ = try await exporter.wavData("1,000", currency: .khr)
            XCTFail("Expected MissingAudioError")
        } catch let error as MissingAudioError {
            XCTAssertEqual(error.missing, ["km:compound:1000", "km:currency:riel"])
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    func testInvalidInputThrowsAmountError() async {
        do {
            _ = try await AmountAudioExporter().wavData("abc", currency: .khr)
            XCTFail("Expected AmountError")
        } catch {
            XCTAssertEqual(error as? AmountError, .invalidFormat)
        }
    }
}
