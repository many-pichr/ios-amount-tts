import KhmerAmountSpeech
import SwiftUI

struct SpeakView: View {
    @StateObject private var model = SpeechViewModel()

    var body: some View {
        NavigationView {
            Form {
                Section("Amount") {
                    HStack {
                        Text(model.currency.symbol).foregroundColor(.secondary)
                        TextField("Amount", text: $model.amount)
                            .keyboardType(.decimalPad)
                            .font(.title3.monospacedDigit())
                    }
                    Picker("Currency", selection: $model.currency) {
                        ForEach(CurrencyCode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Language", selection: $model.language) {
                        ForEach(SpeechLanguage.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Voice type", selection: $model.voiceType) {
                        ForEach(VoiceType.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Result") {
                    switch model.speech {
                    case .success(let speech):
                        ResultView(speech: speech, activeIndex: model.activeIndex)
                    case .failure(let error):
                        Text(error.localizedDescription).foregroundColor(.red)
                    }
                }

                Section {
                    PlayerControls(model: model)
                }

                Section("Examples (tap to hear)") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 8) {
                        ForEach(AmountExample.all, id: \.self) { example in
                            Button {
                                model.select(example)
                            } label: {
                                Text("\(example.amount) \(example.currency.rawValue)")
                                    .font(.footnote.monospacedDigit().weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 36)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Amount Speech")
        }
        .navigationViewStyle(.stack)
    }
}

private struct ResultView: View {
    let speech: AmountSpeech
    let activeIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if speech.language == .khmer {
                Text("\(speech.amount.formatted) \(speech.amount.currency.rawValue) · \(toKhmerDigits(speech.amount.formatted))")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Text(speech.text)
                .font(.title2)
                .fixedSize(horizontal: false, vertical: true)

            Text("Audio sequence (\(speech.tokens.count) segments)")
                .font(.caption)
                .foregroundColor(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(Array(speech.tokens.enumerated()), id: \.offset) { index, token in
                    TokenChip(token: token, active: index == activeIndex)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct TokenChip: View {
    let token: AudioToken
    let active: Bool

    var body: some View {
        VStack(spacing: 1) {
            Text(token.text).font(.callout)
            Text(token.value).font(.system(size: 9, design: .monospaced)).opacity(0.6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(token.type.color.opacity(active ? 0.45 : 0.12))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(active ? token.type.color : .clear, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .scaleEffect(active ? 1.08 : 1)
        .animation(.easeOut(duration: 0.12), value: active)
    }
}

private struct PlayerControls: View {
    @ObservedObject var model: SpeechViewModel

    private var isActive: Bool { model.state != .idle }
    private var canSpeak: Bool {
        if case .success = model.speech { return model.state != .loading }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if model.state == .playing || model.state == .paused {
                    Button(action: model.togglePause) {
                        Label(model.state == .paused ? "Resume" : "Pause",
                              systemImage: model.state == .paused ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(action: model.speak) {
                        Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSpeak)
                }
                Button(action: model.stop) {
                    Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(!isActive)
            }

            HStack {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(statusText).font(.footnote).foregroundColor(.secondary)
                Spacer()
                if let result = model.lastResult, model.state == .idle {
                    Text("Last: \(result)").font(.footnote).foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading) {
                Text("Word gap: \(Int(model.gapMs)) ms").font(.footnote).foregroundColor(.secondary)
                Slider(value: $model.gapMs, in: -40...150, step: 5)
            }

            if let error = model.playbackError {
                Text(error).font(.footnote).foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusText: String {
        switch model.state {
        case .idle: "Ready"
        case .loading: "Loading audio…"
        case .playing: "Speaking…"
        case .paused: "Paused"
        }
    }

    private var statusColor: Color {
        switch model.state {
        case .idle: .gray
        case .loading, .paused: .orange
        case .playing: .green
        }
    }
}

/// Wraps chips onto multiple lines (iOS 15-compatible; `Layout` needs iOS 16).
private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(iOS 16.0, *) {
            WrappingStack(spacing: spacing) { content() }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) { content() }
            }
        }
    }
}

@available(iOS 16.0, *)
private struct WrappingStack: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(bounds.width, subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ maxWidth: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > maxWidth, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let isFirst = rows[rows.count - 1].indices.isEmpty
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += isFirst ? size.width : size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
