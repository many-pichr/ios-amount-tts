import KhmerAmountSpeech
import SwiftUI

/// Lists every bundled clip so each recording can be checked by ear, and flags missing files.
struct CatalogView: View {
    @StateObject private var model = SpeechViewModel()
    @State private var language: SpeechLanguage = .khmer

    private var groups: [(type: AudioTokenType, assets: [AudioAsset])] {
        AudioTokenType.allCases.compactMap { type in
            let assets = AudioCatalog.assets.filter { $0.language == language && $0.type == type }
            return assets.isEmpty ? nil : (type, assets)
        }
    }

    private var missingCount: Int {
        AudioCatalog.assets.filter { AudioResources.bundledURL(for: $0.token) == nil }.count
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    Picker("Language", selection: $language) {
                        ForEach(SpeechLanguage.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Label(
                        missingCount == 0
                            ? "All \(AudioCatalog.assets.count) clips are bundled"
                            : "\(missingCount) clip(s) missing from the bundle",
                        systemImage: missingCount == 0 ? "checkmark.seal" : "exclamationmark.triangle"
                    )
                    .foregroundColor(missingCount == 0 ? .green : .red)
                    .font(.footnote)
                    if let error = model.playbackError {
                        Text(error).font(.footnote).foregroundColor(.red)
                    }
                }

                ForEach(groups, id: \.type) { group in
                    Section("\(group.type.rawValue) (\(group.assets.count))") {
                        ForEach(group.assets, id: \.id) { asset in
                            Button {
                                model.play([asset.token])
                            } label: {
                                ClipRow(asset: asset)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Clips")
        }
        .navigationViewStyle(.stack)
    }
}

private struct ClipRow: View {
    let asset: AudioAsset

    var body: some View {
        HStack {
            Circle().fill(asset.type.color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.text).foregroundColor(.primary)
                if asset.romanized != asset.text {
                    Text(asset.romanized).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            Text(asset.value).font(.caption.monospaced()).foregroundColor(.secondary)
            if AudioResources.bundledURL(for: asset.token) == nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
            } else {
                Image(systemName: "play.circle").foregroundColor(.accentColor)
            }
        }
    }
}
