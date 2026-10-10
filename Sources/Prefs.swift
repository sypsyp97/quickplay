import Foundation

enum Prefs {
    static let resume = "resumePlayback"
    static let loop = "loopPlayback"
    static let openSize = "openSize"  // "fit" or "actual"
    static let autoHide = "autoHideTitleBar"
    static let recent = "recentFiles"
    static let positions = "playbackPositions"

    static let maxRecent = 10
    static let maxPositions = 200

    // Video types QuickPlay takes over when made the default player.
    static let videoTypes = [
        "public.mpeg-4", "com.apple.quicktime-movie", "com.apple.m4v-video",
        "org.matroska.mkv", "org.webmproject.webm", "com.adobe.flash.video",
        "com.microsoft.windows-media-wmv", "com.microsoft.advanced-systems-format",
        "public.mpeg-2-transport-stream", "public.avchd-mpeg-2-transport-stream",
        "com.real.realmedia", "com.real.realmedia-vbr", "public.avi", "org.xiph.ogv",
        "jp.co.dvdfllc.vob", "public.mpeg", "public.3gpp",
    ]

    static func register() {
        UserDefaults.standard.register(defaults: [
            resume: true, loop: false, openSize: "fit", autoHide: true,
        ])
    }

    static var defaults: UserDefaults { .standard }

    static var recentFiles: [URL] {
        (defaults.stringArray(forKey: recent) ?? []).map { URL(fileURLWithPath: $0) }
    }

    static func addRecent(_ url: URL) {
        var paths = defaults.stringArray(forKey: recent) ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        defaults.set(Array(paths.prefix(maxRecent)), forKey: recent)
    }

    static func clearRecent() {
        defaults.removeObject(forKey: recent)
    }

    static func position(for url: URL) -> Double? {
        (defaults.dictionary(forKey: positions) as? [String: Double])?[url.path]
    }

    static func setPosition(_ seconds: Double?, for url: URL) {
        var all = defaults.dictionary(forKey: positions) as? [String: Double] ?? [:]
        all[url.path] = seconds
        while all.count > maxPositions, let key = all.keys.first(where: { $0 != url.path }) {
            all.removeValue(forKey: key)
        }
        defaults.set(all, forKey: positions)
    }
}
