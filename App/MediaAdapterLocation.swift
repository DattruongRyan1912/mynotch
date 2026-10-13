import Foundation

/// Bundled mediaremote-adapter pieces. `/usr/bin/perl` runs the script, which loads the framework;
/// the app never links the framework itself, it only hands these URLs to the media module.
enum MediaAdapterLocation {
    /// `Contents/Resources/mediaremote-adapter.pl`, or nil when the build did not copy it.
    static var scriptURL: URL? {
        Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl")
    }

    /// `Contents/Frameworks/MediaRemoteAdapter.framework`, or nil when the build did not embed it.
    static var frameworkURL: URL? {
        guard let url = Bundle.main.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework"),
              FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        else { return nil }
        return url
    }
}
