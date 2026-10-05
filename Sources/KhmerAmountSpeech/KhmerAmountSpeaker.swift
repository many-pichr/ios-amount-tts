@preconcurrency import AVFoundation
import Foundation

public enum PlaybackState: Sendable {
    case idle, loading, playing, paused
}

public enum PlaybackStatus: Sendable {
    case completed, stopped
}

public struct PlaybackResult: Sendable {
    public let status: PlaybackStatus
    /// Asset ids skipped because they were unavailable (`MissingAssetPolicy.skip` only).
    public let skipped: [String]
}

public enum MissingAssetPolicy: Sendable {
    /// Refuse to speak a partial amount — in banking, skipping "thousand" would announce the wrong
    /// number. Default.
    case fail
    /// Skip unavailable segments. Only useful during development.
    case skip
}

/// Thrown when segments cannot be loaded and the policy is `.fail`.
public struct MissingAudioError: Error, LocalizedError {
    /// Asset ids, e.g. "km:unit:thousand".
    public let missing: [String]
    public var errorDescription: String? { "Missing audio for: \(missing.joined(separator: ", "))" }
}

/// Speaks amounts by composing bundled, pre-recorded Khmer/English segments.
///
/// Everything is local: no amount or text ever leaves the device, and no TTS service is called.
/// The segments are trimmed, faded and joined into one buffer, so gaps are sample-accurate.
///
///     let speaker = KhmerAmountSpeaker()
///     try await speaker.speak("1,250,000", currency: .khr)                      // Khmer
///     try await speaker.speak("25.50", currency: .usd, language: .english)
///     try await speaker.speak("50,000", currency: .khr, voiceType: .received)   // ទទួលប្រាក់ចំនួន…
@MainActor
public final class KhmerAmountSpeaker {
    public struct Configuration: Sendable {
        public var render: RenderOptions
        /// Output volume 0…1. Default 1.
        public var volume: Float
        public var missingAssetPolicy: MissingAssetPolicy
        /// iOS: set the shared AVAudioSession to `.playback` / `.spokenAudio` (ducking other audio)
        /// before speaking. Disable if your app manages the session itself. Default true.
        public var configuresAudioSession: Bool
        /// Where each segment's audio file lives. Default: the clips bundled with this library.
        /// Return nil for unavailable segments. Use this to ship studio recordings in your app.
        public var resolveURL: @Sendable (AudioToken) -> URL?

        public init(
            render: RenderOptions = RenderOptions(),
            volume: Float = 1,
            missingAssetPolicy: MissingAssetPolicy = .fail,
            configuresAudioSession: Bool = true,
            resolveURL: @escaping @Sendable (AudioToken) -> URL? = AudioResources.bundledURL
        ) {
            self.render = render
            self.volume = volume
            self.missingAssetPolicy = missingAssetPolicy
            self.configuresAudioSession = configuresAudioSession
            self.resolveURL = resolveURL
        }
    }

    public var configuration: Configuration {
        didSet { engine.mainMixerNode.outputVolume = configuration.volume }
    }

    public private(set) var state: PlaybackState = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }

    /// Called when `state` changes.
    public var onStateChange: ((PlaybackState) -> Void)?
    /// Called with the index (into the token list) of the segment currently audible, or nil.
    public var onTokenChange: ((Int?) -> Void)?

    /// Output sample rate of the composed utterance (the bundled clips are 44.1 kHz mono).
    public static let sampleRate: Double = 44_100

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: KhmerAmountSpeaker.sampleRate, channels: 1)!
    private let loader = ClipLoader(sampleRate: KhmerAmountSpeaker.sampleRate)

    private var session = 0
    private var pending: CheckedContinuation<PlaybackResult, Never>?
    private var skipped: [String] = []
    private var rendered: RenderedSequence?
    private var progressTimer: Timer?
    private var currentIndex: Int?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = configuration.volume
    }

    // MARK: Public API

    /// Converts `input` and speaks it. Resolves when playback completes or is stopped.
    @discardableResult
    public func speak(
        _ input: String,
        currency: CurrencyCode,
        language: SpeechLanguage = .khmer,
        voiceType: VoiceType = .amount
    ) async throws -> PlaybackResult {
        let speech = try AmountSpeech(input, currency: currency, language: language, voiceType: voiceType)
        return try await play(speech.tokens)
    }

    /// Speaks a prepared `AmountSpeech`.
    @discardableResult
    public func speak(_ speech: AmountSpeech) async throws -> PlaybackResult {
        try await play(speech.tokens)
    }

    /// Loads and plays `tokens` as one utterance. Calling it again while playing stops the previous
    /// playback first, so utterances never overlap.
    @discardableResult
    public func play(_ tokens: [AudioToken]) async throws -> PlaybackResult {
        stop()
        session += 1
        let session = self.session
        guard !tokens.isEmpty else { return PlaybackResult(status: .completed, skipped: []) }
        state = .loading

        let resolve = configuration.resolveURL
        let loaded = await loader.load(tokens, resolveURL: resolve)
        guard session == self.session else { return PlaybackResult(status: .stopped, skipped: []) }

        let missing = loaded.filter(\.clips.isEmpty).map(\.token.id)
        if !missing.isEmpty, configuration.missingAssetPolicy == .fail {
            state = .idle
            var seen = Set<String>()
            throw MissingAudioError(missing: missing.filter { seen.insert($0).inserted })
        }

        let clips = loaded.enumerated().flatMap { index, item in
            item.clips.map { SequenceRenderer.Clip(tokenIndex: index, samples: $0) }
        }
        let sequence = SequenceRenderer.render(clips, sampleRate: Self.sampleRate, options: configuration.render)
        guard let buffer = makeBuffer(sequence.samples) else {
            state = .idle
            return PlaybackResult(status: .completed, skipped: missing)
        }

        do {
            try startEngine()
        } catch {
            state = .idle
            throw error
        }
        guard session == self.session else { return PlaybackResult(status: .stopped, skipped: []) }

        return await withCheckedContinuation { continuation in
            pending = continuation
            skipped = missing
            rendered = sequence
            player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in
                    guard let self, session == self.session else { return }
                    self.finish(.completed)
                    self.state = .idle
                }
            }
            player.play()
            state = .playing
            startProgress()
        }
    }

    public func pause() {
        guard state == .playing else { return }
        player.pause()
        state = .paused
    }

    public func resume() {
        guard state == .paused else { return }
        player.play()
        state = .playing
    }

    /// Stops playback immediately. Safe to call at any time.
    public func stop() {
        session += 1
        if player.isPlaying || state != .idle { player.stop() }
        finish(.stopped)
        state = .idle
    }

    /// Decodes common segments ahead of time so the first `speak` starts instantly.
    @discardableResult
    public func preload(languages: [SpeechLanguage] = SpeechLanguage.allCases) async -> (loaded: Int, failed: [String]) {
        let tokens = AudioCatalog.assets.filter { $0.preload && languages.contains($0.language) }.map(\.token)
        let loaded = await loader.load(tokens, resolveURL: configuration.resolveURL)
        let failed = loaded.filter(\.clips.isEmpty).map(\.token.id)
        return (loaded.count - failed.count, failed)
    }

    // MARK: Private

    private func startEngine() throws {
        #if os(iOS) || os(tvOS) || os(visionOS)
        if configuration.configuresAudioSession {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true)
        }
        #endif
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }

    private func finish(_ status: PlaybackStatus) {
        stopProgress()
        rendered = nil
        let continuation = pending
        pending = nil
        continuation?.resume(returning: PlaybackResult(status: status, skipped: skipped))
        skipped = []
    }

    private func startProgress() {
        stopProgress()
        let timer = Timer(timeInterval: 0.025, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
        tick()
    }

    private func tick() {
        guard let rendered, let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime)
        else { return }
        let index = rendered.tokenIndex(atSample: Int(playerTime.sampleTime))
        if index != currentIndex {
            currentIndex = index
            onTokenChange?(index)
        }
    }

    private func stopProgress() {
        progressTimer?.invalidate()
        progressTimer = nil
        if currentIndex != nil {
            currentIndex = nil
            onTokenChange?(nil)
        }
    }
}

/// Decodes clips to mono Float samples at a fixed rate, with an in-memory cache.
actor ClipLoader {
    struct Loaded: Sendable {
        let token: AudioToken
        /// One clip, or a compound's parts when its own clip is unavailable. Empty if missing.
        let clips: [[Float]]
    }

    private let sampleRate: Double
    private var cache: [URL: [Float]] = [:]

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    func load(_ tokens: [AudioToken], resolveURL: @Sendable (AudioToken) -> URL?) -> [Loaded] {
        tokens.map { token in
            if let samples = samples(for: token, resolveURL) { return Loaded(token: token, clips: [samples]) }
            // Compound clip unavailable: speak its parts separately instead.
            guard let parts = token.parts, !parts.isEmpty else { return Loaded(token: token, clips: []) }
            let partClips = parts.compactMap { samples(for: $0, resolveURL) }
            return Loaded(token: token, clips: partClips.count == parts.count ? partClips : [])
        }
    }

    private func samples(for token: AudioToken, _ resolveURL: @Sendable (AudioToken) -> URL?) -> [Float]? {
        guard let url = resolveURL(token) else { return nil }
        if let cached = cache[url] { return cached }
        guard let samples = try? decode(url) else { return nil }
        cache[url] = samples
        return samples
    }

    private func decode(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let source = file.processingFormat
        guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(file.length)) else {
            return []
        }
        try file.read(into: input)

        let target = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        var buffer = input
        if source.sampleRate != target.sampleRate || source.channelCount != 1 {
            guard let converter = AVAudioConverter(from: source, to: target) else { return [] }
            let capacity = AVAudioFrameCount(Double(input.frameLength) * target.sampleRate / source.sampleRate) + 1024
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return [] }
            var consumed = false
            var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if consumed {
                    status.pointee = .endOfStream
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return input
            }
            if let error { throw error }
            buffer = output
        }
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }
}
