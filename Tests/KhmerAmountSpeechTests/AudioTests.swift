import XCTest
@testable import KhmerAmountSpeech

final class AudioTests: XCTestCase {
    func testEveryCatalogAssetIsBundled() {
        let missing = AudioCatalog.assets.filter { AudioResources.bundledURL(for: $0.token) == nil }.map(\.id)
        XCTAssertEqual(missing, [])
        XCTAssertEqual(AudioCatalog.assets.filter { $0.language == .khmer }.count, 68)
        XCTAssertEqual(AudioCatalog.assets.filter { $0.language == .english }.count, 77)
    }

    func testCatalogIdsAreUnique() {
        XCTAssertEqual(Set(AudioCatalog.assets.map(\.id)).count, AudioCatalog.assets.count)
    }

    func testDecodesBundledClips() async {
        let loader = ClipLoader(sampleRate: 44_100)
        let tokens = [AudioCatalog.token(.compound, "1000", .khmer), AudioCatalog.token(.currency, "dollars", .english)]
        let loaded = await loader.load(tokens, resolveURL: AudioResources.bundledURL)
        for item in loaded {
            XCTAssertEqual(item.clips.count, 1)
            // Every bundled word is between 0.1 s and 2 s of audio.
            XCTAssertGreaterThan(item.clips[0].count, 4_410)
            XCTAssertLessThan(item.clips[0].count, 88_200)
        }
    }

    func testCompoundFallsBackToParts() async {
        let loader = ClipLoader(sampleRate: 44_100)
        let compound = try! NumberSpeech.tokens(2_000, language: .khmer)[0]
        let withoutCompounds: @Sendable (AudioToken) -> URL? = { token in
            token.type == .compound ? nil : AudioResources.bundledURL(for: token)
        }
        let loaded = await loader.load([compound], resolveURL: withoutCompounds)
        XCTAssertEqual(loaded[0].clips.count, 2)

        let nothing: @Sendable (AudioToken) -> URL? = { _ in nil }
        let missing = await loader.load([compound], resolveURL: nothing)
        XCTAssertEqual(missing[0].clips.count, 0)
    }

    // MARK: SequenceRenderer (sample rate 1000 → 1 sample per ms)

    private func clip(_ index: Int, lead: Int = 20, speech: Int = 200, tail: Int = 30) -> SequenceRenderer.Clip {
        SequenceRenderer.Clip(tokenIndex: index,
                              samples: Array(repeating: 0, count: lead) + Array(repeating: 0.5, count: speech)
                                  + Array(repeating: 0, count: tail))
    }

    func testTrimsSilenceAndInsertsGap() {
        let options = RenderOptions(gapMs: 30, fadeMs: 0, trimPaddingMs: 0)
        let out = SequenceRenderer.render([clip(0), clip(1)], sampleRate: 1000, options: options)
        XCTAssertEqual(out.segments.map(\.range), [0..<200, 230..<430])
        XCTAssertEqual(out.samples.count, 430)
        XCTAssertEqual(out.samples[215], 0)
        XCTAssertEqual(out.tokenIndex(atSample: 300), 1)
        XCTAssertNil(out.tokenIndex(atSample: 215))
    }

    func testNegativeGapCrossfades() {
        let options = RenderOptions(gapMs: -20, fadeMs: 0, trimPaddingMs: 0)
        let out = SequenceRenderer.render([clip(0), clip(1)], sampleRate: 1000, options: options)
        XCTAssertEqual(out.segments[1].range.lowerBound, 180)
        XCTAssertEqual(out.samples[190], 1.0, accuracy: 0.0001) // both words mixed
    }

    func testFadeEnvelope() {
        let options = RenderOptions(gapMs: 0, fadeMs: 8, trimPaddingMs: 0)
        let out = SequenceRenderer.render([clip(0)], sampleRate: 1000, options: options)
        XCTAssertEqual(out.samples[0], 0)
        XCTAssertEqual(out.samples[4], 0.25, accuracy: 0.0001)
        XCTAssertEqual(out.samples[100], 0.5)
        XCTAssertEqual(out.samples[199], 0)
    }

    func testFallbackClipsShareTokenIndex() {
        let out = SequenceRenderer.render([clip(0), clip(0), clip(1)], sampleRate: 1000)
        XCTAssertEqual(out.segments.map(\.tokenIndex), [0, 0, 1])
    }
}
