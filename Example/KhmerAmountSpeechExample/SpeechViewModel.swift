import KhmerAmountSpeech
import SwiftUI

/// Wraps KhmerAmountSpeaker for SwiftUI: playback state, the highlighted token and errors.
@MainActor
final class SpeechViewModel: ObservableObject {
    @Published var amount = "1,250,000"
    @Published var currency: CurrencyCode = .khr
    @Published var language: SpeechLanguage = .khmer
    @Published var voiceType: VoiceType = .amount
    @Published var gapMs: Double = 30 {
        didSet { speaker.configuration.render.gapMs = gapMs }
    }

    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var activeIndex: Int?
    @Published private(set) var playbackError: String?
    @Published private(set) var lastResult: String?

    let speaker = KhmerAmountSpeaker()

    init() {
        speaker.onStateChange = { [weak self] in self?.state = $0 }
        speaker.onTokenChange = { [weak self] in self?.activeIndex = $0 }
        Task { await speaker.preload() }
    }

    /// The converted amount, or the input error. Recomputed live while typing.
    var speech: Result<AmountSpeech, Error> {
        Result { try AmountSpeech(amount, currency: currency, language: language, voiceType: voiceType) }
    }

    func speak() {
        guard case .success(let speech) = speech else { return }
        play(speech.tokens)
    }

    func play(_ tokens: [AudioToken]) {
        playbackError = nil
        Task {
            do {
                let result = try await speaker.play(tokens)
                lastResult = result.status == .completed ? "Completed" : "Stopped"
            } catch {
                playbackError = error.localizedDescription
            }
        }
    }

    func select(_ example: AmountExample) {
        amount = example.amount
        currency = example.currency
        speak()
    }

    func togglePause() {
        state == .paused ? speaker.resume() : speaker.pause()
    }

    func stop() {
        speaker.stop()
    }
}

struct AmountExample: Hashable {
    let amount: String
    let currency: CurrencyCode

    static let all: [AmountExample] = [
        .init(amount: "1,000", currency: .khr),
        .init(amount: "10,000", currency: .khr),
        .init(amount: "25,500", currency: .khr),
        .init(amount: "125,000", currency: .khr),
        .init(amount: "1,250,000", currency: .khr),
        .init(amount: "10,500,000", currency: .khr),
        .init(amount: "1,250,000,000", currency: .khr),
        .init(amount: "12.50", currency: .usd),
        .init(amount: "25.50", currency: .usd),
        .init(amount: "1,000,000", currency: .usd),
    ]
}

extension SpeechLanguage {
    var label: String {
        switch self {
        case .khmer: "ខ្មែរ"
        case .english: "English"
        }
    }
}

extension VoiceType {
    var label: String {
        switch self {
        case .amount: "Amount"
        case .confirmPay: "Confirm pay"
        case .received: "Received"
        }
    }
}

extension AudioTokenType {
    var color: Color {
        switch self {
        case .number: .blue
        case .unit: .orange
        case .compound: .pink
        case .currency: .green
        case .connector: .gray
        case .phrase: .purple
        }
    }
}
