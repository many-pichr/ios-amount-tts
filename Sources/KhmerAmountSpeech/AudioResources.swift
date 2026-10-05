import Foundation

/// Locates the audio clips bundled with the library (CocoaPods resource bundle or SwiftPM
/// `Bundle.module`). Both keep the folder layout `audio/<lang>/<type>/<value>.mp3`.
public enum AudioResources {
    /// Bundle containing the `audio` folder.
    public static let bundle: Bundle = {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        let host = Bundle(for: BundleToken.self)
        if let url = host.url(forResource: "KhmerAmountSpeech", withExtension: "bundle"),
           let resources = Bundle(url: url) {
            return resources
        }
        return host
        #endif
    }()

    /// URL of a token's bundled clip, or nil if the clip is not shipped.
    @Sendable
    public static func bundledURL(for token: AudioToken) -> URL? {
        let path = token.resourcePath as NSString
        return bundle.url(
            forResource: path.lastPathComponent,
            withExtension: "mp3",
            subdirectory: path.deletingLastPathComponent
        )
    }

    /// Builds a resolver for clips stored in your own bundle or folder with the same layout
    /// (`<root>/audio/<lang>/<type>/<value>.mp3`), e.g. professional studio recordings. Tokens
    /// without a file there fall back to the bundled clips.
    public static func resolver(root: URL) -> @Sendable (AudioToken) -> URL? {
        { token in
            let url = root.appendingPathComponent(token.resourcePath).appendingPathExtension("mp3")
            return FileManager.default.fileExists(atPath: url.path) ? url : bundledURL(for: token)
        }
    }
}

#if !SWIFT_PACKAGE
private final class BundleToken {}
#endif
