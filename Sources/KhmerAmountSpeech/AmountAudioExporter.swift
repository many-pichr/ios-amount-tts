import Foundation

/// Sample format of exported WAV files.
public enum WAVSampleFormat: Sendable {
    /// 16-bit signed integer PCM — the most compatible choice. Default.
    case pcm16
    /// 32-bit IEEE float PCM — lossless copy of the rendered samples.
    case float32
}

/// Renders amounts to WAV audio without playing them — e.g. to send to a payment terminal,
/// cache per transaction, attach to a notification, or play with your own audio stack.
///
/// The output is exactly what `KhmerAmountSpeaker` plays: mono, 44.1 kHz, with the same trimming,
/// fades, gaps and compound fallback. Safe to use from any thread or task.
///
///     let exporter = AmountAudioExporter()
///     let wav = try await exporter.wavData("1,250,000", currency: .khr)               // Data
///     try await exporter.writeWAV("50,000", currency: .khr, voiceType: .received, to: fileURL)
public final class AmountAudioExporter: Sendable {
    public let render: RenderOptions
    public let missingAssetPolicy: MissingAssetPolicy
    public let sampleFormat: WAVSampleFormat
    private let resolveURL: @Sendable (AudioToken) -> URL?
    private let loader = ClipLoader(sampleRate: AmountAudioExporter.sampleRate)

    /// Sample rate of exported audio (the bundled clips are 44.1 kHz mono).
    public static let sampleRate: Double = KhmerAmountSpeaker.sampleRate

    public init(
        render: RenderOptions = RenderOptions(),
        missingAssetPolicy: MissingAssetPolicy = .fail,
        sampleFormat: WAVSampleFormat = .pcm16,
        resolveURL: @escaping @Sendable (AudioToken) -> URL? = AudioResources.bundledURL
    ) {
        self.render = render
        self.missingAssetPolicy = missingAssetPolicy
        self.sampleFormat = sampleFormat
        self.resolveURL = resolveURL
    }

    // MARK: WAV data

    /// Converts `input` and returns the spoken amount as a WAV file in memory.
    public func wavData(
        _ input: String,
        currency: CurrencyCode,
        language: SpeechLanguage = .khmer,
        voiceType: VoiceType = .amount
    ) async throws -> Data {
        try await wavData(for: AmountSpeech(input, currency: currency, language: language, voiceType: voiceType))
    }

    public func wavData(for speech: AmountSpeech) async throws -> Data {
        try await wavData(for: speech.tokens)
    }

    public func wavData(for tokens: [AudioToken]) async throws -> Data {
        let sequence = try await renderSequence(tokens)
        return WAVEncoder.encode(sequence.samples, sampleRate: sequence.sampleRate, format: sampleFormat)
    }

    // MARK: WAV files

    /// Converts `input` and writes the spoken amount to a `.wav` file (overwriting it).
    public func writeWAV(
        _ input: String,
        currency: CurrencyCode,
        language: SpeechLanguage = .khmer,
        voiceType: VoiceType = .amount,
        to url: URL
    ) async throws {
        try await wavData(input, currency: currency, language: language, voiceType: voiceType)
            .write(to: url, options: .atomic)
    }

    public func writeWAV(for speech: AmountSpeech, to url: URL) async throws {
        try await wavData(for: speech).write(to: url, options: .atomic)
    }

    public func writeWAV(for tokens: [AudioToken], to url: URL) async throws {
        try await wavData(for: tokens).write(to: url, options: .atomic)
    }

    // MARK: Text to speech file

    /// Converts `input` to speech, saves it as a `.wav` file and returns the file's URL
    /// (use `.path` for a path string).
    ///
    ///     let url = try await exporter.speechWAV("50,000", currency: .khr, voiceType: .received)
    ///     url.path   // ".../tmp/KhmerAmountSpeech/<UUID>.wav"
    ///
    /// - Parameters:
    ///   - directory: Folder to write into, created if needed. Defaults to
    ///     `<temporary directory>/KhmerAmountSpeech`; the system may purge it, so move the file if you keep it.
    ///   - fileName: File name, with or without the `.wav` extension. Defaults to a new UUID so calls
    ///     never overwrite each other. An existing file with the same name is replaced.
    @discardableResult
    public func speechWAV(
        _ input: String,
        currency: CurrencyCode,
        language: SpeechLanguage = .khmer,
        voiceType: VoiceType = .amount,
        directory: URL? = nil,
        fileName: String? = nil
    ) async throws -> URL {
        try await speechWAV(
            for: AmountSpeech(input, currency: currency, language: language, voiceType: voiceType),
            directory: directory,
            fileName: fileName
        )
    }

    @discardableResult
    public func speechWAV(for speech: AmountSpeech, directory: URL? = nil, fileName: String? = nil) async throws -> URL {
        try await speechWAV(for: speech.tokens, directory: directory, fileName: fileName)
    }

    @discardableResult
    public func speechWAV(for tokens: [AudioToken], directory: URL? = nil, fileName: String? = nil) async throws -> URL {
        let folder = directory ?? Self.defaultDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var url = folder.appendingPathComponent(fileName ?? UUID().uuidString)
        if url.pathExtension.lowercased() != "wav" { url.appendPathExtension("wav") }
        try await writeWAV(for: tokens, to: url)
        return url
    }

    /// Default folder for `speechWAV`: `<temporary directory>/KhmerAmountSpeech`.
    public static var defaultDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("KhmerAmountSpeech", isDirectory: true)
    }

    // MARK: Raw samples

    /// The rendered utterance as mono Float samples, with the sample range of each token.
    public func renderSequence(_ tokens: [AudioToken]) async throws -> RenderedSequence {
        try await composeUtterance(
            tokens, loader: loader, options: render, missingAssetPolicy: missingAssetPolicy, resolveURL: resolveURL
        ).sequence
    }
}

/// Loads `tokens` (falling back from compounds to their parts) and joins them into one utterance.
/// Shared by playback and export so both produce identical audio.
func composeUtterance(
    _ tokens: [AudioToken],
    loader: ClipLoader,
    options: RenderOptions,
    missingAssetPolicy: MissingAssetPolicy,
    resolveURL: @escaping @Sendable (AudioToken) -> URL?
) async throws -> (sequence: RenderedSequence, skipped: [String]) {
    let loaded = await loader.load(tokens, resolveURL: resolveURL)
    var seen = Set<String>()
    let missing = loaded.filter(\.clips.isEmpty).map(\.token.id).filter { seen.insert($0).inserted }
    if !missing.isEmpty, missingAssetPolicy == .fail {
        throw MissingAudioError(missing: missing)
    }
    let clips = loaded.enumerated().flatMap { index, item in
        item.clips.map { SequenceRenderer.Clip(tokenIndex: index, samples: $0) }
    }
    let sequence = SequenceRenderer.render(clips, sampleRate: KhmerAmountSpeaker.sampleRate, options: options)
    return (sequence, missing)
}

/// Minimal RIFF/WAVE writer for mono audio.
public enum WAVEncoder {
    public static func encode(_ samples: [Float], sampleRate: Double, format: WAVSampleFormat = .pcm16) -> Data {
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = format == .pcm16 ? 16 : 32
        let formatTag: UInt16 = format == .pcm16 ? 1 : 3 // 1 = PCM, 3 = IEEE float
        let bytesPerFrame = UInt32(channels) * UInt32(bitsPerSample / 8)
        let rate = UInt32(sampleRate.rounded())
        let dataSize = UInt32(samples.count) * bytesPerFrame

        var data = Data(capacity: 44 + Int(dataSize))
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }

        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))
        append(formatTag)
        append(channels)
        append(rate)
        append(rate * bytesPerFrame)
        append(UInt16(bytesPerFrame))
        append(bitsPerSample)
        data.append(contentsOf: Array("data".utf8))
        append(dataSize)

        switch format {
        case .pcm16:
            for sample in samples {
                append(Int16((max(-1, min(1, sample)) * Float(Int16.max)).rounded()))
            }
        case .float32:
            for sample in samples { append(sample.bitPattern) }
        }
        return data
    }
}
