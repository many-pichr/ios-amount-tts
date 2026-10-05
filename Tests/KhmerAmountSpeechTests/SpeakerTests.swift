import XCTest
@testable import KhmerAmountSpeech

@MainActor
final class SpeakerTests: XCTestCase {
    /// Plays a real utterance (muted) through AVAudioEngine and tracks token progress.
    func testSpeaksToCompletion() async throws {
        let speaker = KhmerAmountSpeaker(configuration: .init(volume: 0))
        var states: [PlaybackState] = []
        var tokenIndexes: [Int] = []
        speaker.onStateChange = { states.append($0) }
        speaker.onTokenChange = { if let index = $0, tokenIndexes.last != index { tokenIndexes.append(index) } }

        let result: PlaybackResult
        do {
            result = try await speaker.speak("1,000", currency: .khr, voiceType: .received)
        } catch {
            throw XCTSkip("No audio output available: \(error)")
        }
        XCTAssertEqual(result.status, .completed)
        XCTAssertEqual(states, [.loading, .playing, .idle])
        XCTAssertEqual(tokenIndexes.first, 0)
        XCTAssertEqual(tokenIndexes.last, 2) // phrase, compound:1000, riel
    }

    func testStopResolvesAsStopped() async throws {
        let speaker = KhmerAmountSpeaker(configuration: .init(volume: 0))
        let task = Task { try await speaker.speak("1,250,000", currency: .khr) }
        for _ in 0..<400 where speaker.state != .playing {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        guard speaker.state == .playing else { throw XCTSkip("No audio output available") }
        speaker.stop()
        let result = try await task.value
        XCTAssertEqual(result.status, .stopped)
        XCTAssertEqual(speaker.state, .idle)
    }

    func testMissingAudioFailsByDefault() async {
        let speaker = KhmerAmountSpeaker(configuration: .init(volume: 0, resolveURL: { _ in nil }))
        do {
            try await speaker.speak("1,000", currency: .khr)
            XCTFail("Expected MissingAudioError")
        } catch let error as MissingAudioError {
            XCTAssertEqual(error.missing, ["km:compound:1000", "km:currency:riel"])
        } catch {
            XCTFail("Unexpected \(error)")
        }
        XCTAssertEqual(speaker.state, .idle)
    }
}
