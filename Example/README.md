# KhmerAmountSpeech example app

A SwiftUI app for trying out the library on a simulator or an iPhone. It installs the pod from this
repository (`pod 'KhmerAmountSpeech', :path => '../'`), the same way an app installs the published pod.

- **Speak tab:**
  - Type an amount, then pick the currency (KHR/USD), language (ខ្មែរ/English) and voice type
    (Amount / Confirm pay / Received).
  - Shows the converted text and the clip sequence, and highlights each clip while it plays.
  - Has Play / Pause / Resume / Stop, a word-gap slider (−40…150 ms) and example amounts you can tap.
- **Clips tab:** lists all 145 bundled recordings by language and type. Tap one to hear it. The tab
  also reports any clip missing from the bundle.

## Run

```sh
cd Example
pod install                               # creates KhmerAmountSpeechExample.xcworkspace
open KhmerAmountSpeechExample.xcworkspace
```

Choose a simulator or your iPhone and press Run. To run on a device, set your Team under
Signing & Capabilities and change the bundle id (`com.example.khmeramountspeech.demo`).

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen).
After adding or removing source files, run `xcodegen generate && pod install`.

Command-line build:

```sh
xcodebuild -workspace KhmerAmountSpeechExample.xcworkspace -scheme KhmerAmountSpeechExample \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```
