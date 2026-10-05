import Foundation

/// How segments are joined into one utterance.
public struct RenderOptions: Hashable, Sendable {
    /// Silence between words in ms. Negative values overlap neighbouring words (crossfade). Default 30.
    public var gapMs: Double
    /// Fade-in/out applied to each segment in ms (anti-click). Default 8.
    public var fadeMs: Double
    /// Trim leading/trailing silence in each clip. Default true.
    public var trimSilence: Bool
    /// Linear amplitude treated as silence when trimming. Default 0.01 (≈ -40 dBFS).
    public var silenceThreshold: Float
    /// Audio kept before/after the detected speech when trimming, in ms. Default 12.
    public var trimPaddingMs: Double

    public init(gapMs: Double = 30, fadeMs: Double = 8, trimSilence: Bool = true,
                silenceThreshold: Float = 0.01, trimPaddingMs: Double = 12) {
        self.gapMs = gapMs
        self.fadeMs = fadeMs
        self.trimSilence = trimSilence
        self.silenceThreshold = silenceThreshold
        self.trimPaddingMs = trimPaddingMs
    }
}

/// A mono utterance plus where each token sits in it (for highlighting).
public struct RenderedSequence: Sendable {
    public struct Segment: Hashable, Sendable {
        public let tokenIndex: Int
        /// Sample range in `samples`.
        public let range: Range<Int>
    }

    public let samples: [Float]
    public let sampleRate: Double
    public let segments: [Segment]

    public var duration: TimeInterval { Double(samples.count) / sampleRate }

    /// Index of the token audible at `sample`, if any.
    public func tokenIndex(atSample sample: Int) -> Int? {
        segments.last { $0.range.contains(sample) }?.tokenIndex
    }
}

/// Joins mono clips into one buffer, sample-accurately. Pure and platform-independent, so the
/// timing rules can be unit-tested without an audio device.
public enum SequenceRenderer {
    /// One decoded clip belonging to the token at `tokenIndex`. A compound that fell back to its
    /// parts contributes several clips with the same index.
    public struct Clip: Sendable {
        public let tokenIndex: Int
        public let samples: [Float]

        public init(tokenIndex: Int, samples: [Float]) {
            self.tokenIndex = tokenIndex
            self.samples = samples
        }
    }

    /// Region of `samples` that contains speech, padded by `paddingSamples`.
    public static func speechRange(_ samples: [Float], threshold: Float, paddingSamples: Int) -> Range<Int> {
        guard let first = samples.firstIndex(where: { abs($0) >= threshold }),
              let last = samples.lastIndex(where: { abs($0) >= threshold })
        else { return 0..<samples.count }
        return max(0, first - paddingSamples)..<min(samples.count, last + 1 + paddingSamples)
    }

    public static func render(_ clips: [Clip], sampleRate: Double, options: RenderOptions = RenderOptions()) -> RenderedSequence {
        let ms = { (value: Double) in Int((value / 1000 * sampleRate).rounded()) }
        let gap = ms(options.gapMs)
        var output: [Float] = []
        var segments: [RenderedSequence.Segment] = []
        var cursor = 0

        for clip in clips {
            let range = options.trimSilence
                ? speechRange(clip.samples, threshold: options.silenceThreshold, paddingSamples: ms(options.trimPaddingMs))
                : 0..<clip.samples.count
            let length = range.count
            guard length > 0 else { continue }
            let fade = min(ms(options.fadeMs), length / 4)
            let start = cursor
            if output.count < start + length { output.append(contentsOf: repeatElement(0, count: start + length - output.count)) }

            for i in 0..<length {
                var gain: Float = 1
                if fade > 0 {
                    if i < fade { gain = Float(i) / Float(fade) }
                    else if i >= length - fade { gain = Float(length - 1 - i) / Float(fade) }
                }
                // Mix (not overwrite) so negative gaps crossfade.
                output[start + i] += clip.samples[range.lowerBound + i] * gain
            }

            segments.append(.init(tokenIndex: clip.tokenIndex, range: start..<(start + length)))
            // Negative gaps overlap words but never by more than half a word.
            cursor = start + max(length + gap, length / 2)
        }
        return RenderedSequence(samples: output, sampleRate: sampleRate, segments: segments)
    }
}
