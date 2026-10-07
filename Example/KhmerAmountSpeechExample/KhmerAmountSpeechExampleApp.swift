import SwiftUI

@main
struct KhmerAmountSpeechExampleApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                SpeakView()
                    .tabItem { Label("Speak", systemImage: "speaker.wave.2") }
                CatalogView()
                    .tabItem { Label("Clips", systemImage: "waveform") }
            }
        }
    }
}
