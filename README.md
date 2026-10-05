# KhmerAmountSpeech

Offline Khmer and English speech for money amounts on iOS.

```swift
let speaker = KhmerAmountSpeaker()
try await speaker.speak("1,250,000", currency: .khr)
// 🔊 មួយលានពីរសែនប្រាំម៉ឺនរៀល
```

- **Offline and private.** The library ships about 145 short clips (1.5 MB) and joins them on the device.
  It never calls a TTS service, and no amount leaves the phone.
- **Natural round amounts.** 100 … 900,000 and 1,000,000 are pre-recorded as single phrases
  (មួយពាន់, ពីរម៉ឺន, "two hundred thousand"). If one of those clips is missing, the player
  speaks its separate words instead.
- **Khmer and English.** Khmer uses the formal reading (…ប្រាំម៉ឺន). English uses the short scale.
- **Voice types:** amount only, confirm pay and received.
- **Sample-accurate timing.** Each clip is trimmed, faded and joined into one buffer with a gap you can
  adjust or a crossfade, then played with `AVAudioEngine`.
- KHR and USD (with cents), from 0 to 999,999,999,999.

## Installation

### CocoaPods

```ruby
platform :ios, '13.0'
use_frameworks!

target 'YourApp' do
  use_frameworks!

  pod 'KhmerAmountSpeech',
      :git => 'https://github.com/many-pichr/ios-amount-tts.git',
      :tag => '1.0.0'
end
```

### Swift Package Manager

```swift
.package(url: "https://github.com/your-org/KhmerAmountSpeech.git", from: "1.0.0")
```

Requires iOS 13 or later and Swift 5.9 or later.

## Usage

### Speak an amount

```swift
import KhmerAmountSpeech

@MainActor
final class PaymentAnnouncer {
    private let speaker = KhmerAmountSpeaker()

    func announce() async {
        do {
            try await speaker.speak("50,000", currency: .khr, voiceType: .received)
            // ទទួលប្រាក់ចំនួនប្រាំម៉ឺនរៀល
            try await speaker.speak("25.50", currency: .usd, language: .english, voiceType: .confirmPay)
            // The amount is twenty-five dollars fifty cents, please verify
        } catch let error as AmountError {
            print(error.localizedDescription)      // invalid input
        } catch {
            print(error.localizedDescription)      // missing audio or no audio output
        }
    }
}
```

`speak` returns when playback finishes, with `.completed` or `.stopped`. Starting a new
utterance stops the one that's playing, so utterances never overlap.

| Voice type    | Khmer                                  | English                                 |
| ------------- | -------------------------------------- | --------------------------------------- |
| `.amount`     | {{amount}}                             | {{amount}}                              |
| `.confirmPay` | ទឹកប្រាក់ចំនួន{{amount}} សូមផ្ទៀងផ្ទាត់   | The amount is {{amount}}, please verify |
| `.received`   | ទទួលប្រាក់ចំនួន{{amount}}                | Received {{amount}}                     |

### Text only (no audio)

```swift
let speech = try AmountSpeech("1,250,000", currency: .khr)
speech.text                 // "មួយលានពីរសែនប្រាំម៉ឺនរៀល"
speech.tokens.map(\.id)     // ["km:compound:1000000", "km:compound:200000", "km:compound:50000", "km:currency:riel"]
speech.amount.formatted     // "1,250,000"
toKhmerDigits("1,250,000")  // "១,២៥០,០០០"

try NumberSpeech.speak(125_000, language: .english).text   // "one hundred twenty-five thousand"
```

### Controls and progress

```swift
speaker.pause()
speaker.resume()
speaker.stop()

speaker.onStateChange = { state in /* .idle, .loading, .playing, .paused */ }
speaker.onTokenChange = { index in /* highlight speech.tokens[index] */ }

await speaker.preload()     // decode common clips at launch, so the first speak starts instantly
```

### SwiftUI

```swift
struct AmountView: View {
    @State private var speaker = KhmerAmountSpeaker()   // one speaker for the view's lifetime
    @State private var amount = "1,250,000"

    var body: some View {
        VStack {
            TextField("Amount", text: $amount).keyboardType(.decimalPad)
            Text((try? AmountSpeech(amount, currency: .khr).text) ?? "")
            Button("Speak") { Task { try? await speaker.speak(amount, currency: .khr) } }
        }
    }
}
```

### Configuration

```swift
var config = KhmerAmountSpeaker.Configuration()
config.render.gapMs = 20                 // silence between words; negative values crossfade
config.render.fadeMs = 8                 // fade at each end of a clip, to avoid clicks
config.volume = 1.0
config.missingAssetPolicy = .fail        // refuse to speak a partial amount (default)
config.configuresAudioSession = true     // .playback / .spokenAudio, ducks other audio
let speaker = KhmerAmountSpeaker(configuration: config)
```

#### Using your own recordings

The bundled clips are TTS-generated: Khmer uses `km-KH-SreymomNeural` and English uses
`en-US-JennyNeural`. They're fine for prototyping. For production, record the same phrases with a
professional voice artist and put them in your app bundle using the same layout:

```
Recordings/audio/km/numbers/1.mp3
Recordings/audio/km/compounds/1000.mp3
Recordings/audio/km/phrases/received-prefix.mp3
…
```

```swift
let root = Bundle.main.url(forResource: "Recordings", withExtension: nil)!
config.resolveURL = AudioResources.resolver(root: root)   // falls back to bundled clips
```

`AudioCatalog.assets` lists every phrase, with its text and romanization, to use as a script for the
recording session.

## How it works

```
"1,250,000" ─ ParsedAmount ─ NumberSpeech ─ AmountSpeech (voice type phrases)
                                   │
     [km:compound:1000000, km:compound:200000, km:compound:50000, km:currency:riel]
                                   │
   ClipLoader (decode + cache, compound → parts fallback) ─ SequenceRenderer (trim, fade, gap)
                                   │
                    AVAudioEngine / AVAudioPlayerNode (one buffer)
```

The catalog (`AudioCatalog`) and the reading rules match the
[khmer-amount-speech](../khmer-amount-speech) web app, so the same recordings work on both.

## Example app

`Example/` contains a SwiftUI demo app that has the Speak and Clips screens. See
[Example/README.md](Example/README.md). To run it: `cd Example && pod install && open KhmerAmountSpeechExample.xcworkspace`.

## Development

```sh
swift test                                # unit tests and muted playback tests (macOS)
pod lib lint --allow-warnings             # builds the pod and runs its tests on the iOS simulator
```
# ios-amount-tts
