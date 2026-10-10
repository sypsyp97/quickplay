// Minimal video viewer for double-click: a borderless-looking window with the system
// AVPlayerView inline controls (the same control bar Quick Look shows).
// F, Ctrl-Cmd-F or a double-click on the picture toggles full screen; Esc leaves full
// screen and then closes. The title bar fades out with the controls. Closing the video
// window quits the app. Menus live in Menu.swift, file actions in FileActions.swift.
import AVFoundation
import AVKit
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow?
    let playerView = AVPlayerView()
    var currentURL: URL?
    var audioGroup: AVMediaSelectionGroup?
    var subtitleGroup: AVMediaSelectionGroup?
    var hasAudio = false
    // Taps the frames the player shows, so Copy Frame copies exactly what is on screen.
    var videoOutput: AVPlayerItemVideoOutput?
    // The output hands out each frame once; a second grab while paused reuses this one.
    var lastFrame: (time: CMTime, image: CGImage)?
    var frameDuration = 1.0 / 30
    var settingsWindow: NSWindow?
    var videoSize = CGSize(width: 16, height: 9)
    private(set) var openRequests = 0
    private var chromeTimer: Timer?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    var openPanelShown = false
    // False until the saved position is restored, so an early close keeps the old record.
    private var positionReady = false

    var player: AVPlayer? { playerView.player }

    func applicationWillFinishLaunching(_ notification: Notification) {
        Prefs.register()
        playerView.controlsStyle = .inline
        // Full screen goes through the window (green button, F) only; the player's own
        // full-screen button would open a separate window that bypasses the shortcuts.
        playerView.showsFullScreenToggleButton = false
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(toggleFullScreen))
        doubleClick.numberOfClicksRequired = 2
        doubleClick.delaysPrimaryMouseButtonEvents = false
        playerView.addGestureRecognizer(doubleClick)
        NSApp.mainMenu = makeMainMenu()
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) == true ? nil : event
        }
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] event in
            if event.window === self?.window { self?.showChrome() }
            return event
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        open(url)
    }

    // Launched without a file, or Dock icon clicked with no window: ask for one.
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        guard openRequests == 0, window == nil else { return false }
        DispatchQueue.main.async {
            // A file may have arrived after this was scheduled.
            guard self.openRequests == 0, self.window == nil, !self.openPanelShown else { return }
            self.openDocument(nil)
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        savePosition()
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        savePosition()
        player?.pause()
        // The video window is the app; quit even if Settings is still open.
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        guard let window else { return }
        fit(window)
        showChrome()
    }

    @objc func mouseExited(with event: NSEvent) {
        setChrome(visible: false)
    }

    @objc func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }

    func open(_ url: URL) {
        openRequests += 1
        let request = openRequests
        Task { @MainActor in await self.show(url, request: request) }
    }

    @MainActor
    private func show(_ url: URL, request: Int) async {
        let asset = AVURLAsset(url: url)
        let size = await displaySize(of: asset)
        let audio = try? await asset.loadMediaSelectionGroup(for: .audible)
        let legible = try? await asset.loadMediaSelectionGroup(for: .legible)
        let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        let videoTrack = try? await asset.loadTracks(withMediaType: .video).first
        let fps = (try? await videoTrack?.load(.nominalFrameRate)) ?? 0
        // A newer open arrived while this one loaded its metadata.
        guard request == openRequests else { return }

        savePosition()
        positionReady = false
        videoSize = size
        currentURL = url
        audioGroup = audio
        subtitleGroup = legible
        hasAudio = !audioTracks.isEmpty
        frameDuration = fps > 0 ? 1 / Double(fps) : 1.0 / 30

        let item = AVPlayerItem(asset: asset)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(output)
        videoOutput = output
        lastFrame = nil
        let player = AVPlayer(playerItem: item)
        // No AirPlay route button in the corner.
        player.allowsExternalPlayback = false
        playerView.player = player
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.didPlayToEnd() }
        }
        let resumeAt = Prefs.defaults.bool(forKey: Prefs.resume) ? Prefs.position(for: url) : nil
        // Restore the saved position once the item can seek, then start playback.
        statusObservation = item.observe(\.status, options: [.initial]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self, self.player?.currentItem === item else { return }
                switch item.status {
                case .readyToPlay:
                    self.statusObservation = nil
                    guard let resumeAt else { return self.startPlayback(player) }
                    player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600),
                                toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                        // An unfinished seek means the user seeked meanwhile; their position wins.
                        DispatchQueue.main.async {
                            guard self.player === player else { return }
                            self.startPlayback(player)
                        }
                    }
                case .failed:
                    self.statusObservation = nil
                    self.showError("Cannot play \(url.lastPathComponent): \(item.error?.localizedDescription ?? "unknown error")")
                default:
                    break
                }
            }
        }
        Prefs.addRecent(url)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)

        let window = self.window ?? makeWindow()
        self.window = window
        window.title = url.lastPathComponent
        if !window.styleMask.contains(.fullScreen) {
            window.contentAspectRatio = videoSize
            let wantsActual = Prefs.defaults.string(forKey: Prefs.openSize) == "actual"
            window.setFrame(wantsActual ? actualFrame(window) : fittedFrame(window, fraction: 0.8), display: true)
        }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(playerView)
        NSApp.activate()
        showChrome()
    }

    private func startPlayback(_ player: AVPlayer) {
        positionReady = true
        player.play()
        showChrome()
    }

    private func didPlayToEnd() {
        guard let player else { return }
        if Prefs.defaults.bool(forKey: Prefs.loop) {
            player.seek(to: .zero)
            player.play()
        } else if let currentURL {
            Prefs.setPosition(nil, for: currentURL)
        }
    }

    // Remembers where playback stopped, unless it is near the start or the end.
    func savePosition() {
        guard positionReady, let currentURL, let player, let item = player.currentItem else { return }
        let time = player.currentTime().seconds
        let duration = item.duration.seconds
        // Unknown time or duration: keep whatever record exists.
        guard time.isFinite, duration.isFinite else { return }
        let keep = Prefs.defaults.bool(forKey: Prefs.resume) && time > 5 && time < duration - 5
        Prefs.setPosition(keep ? time : nil, for: currentURL)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        window.contentMinSize = NSSize(width: 360, height: 200)
        window.delegate = self
        window.contentView = playerView
        playerView.addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
        return window
    }

    // MARK: Window size

    func fit(_ window: NSWindow) {
        window.contentAspectRatio = videoSize
        window.setFrame(fittedFrame(window, fraction: 0.8), display: true)
    }

    // Largest frame with the video's aspect ratio inside a fraction of the screen, centered.
    func fittedFrame(_ window: NSWindow, fraction: CGFloat) -> NSRect {
        let area = (window.screen ?? NSScreen.main!).visibleFrame
        let scale = min(area.width * fraction / videoSize.width, area.height * fraction / videoSize.height)
        return centered(NSSize(width: videoSize.width * scale, height: videoSize.height * scale), in: area)
    }

    // One video pixel per point, shrunk to the screen when the video is larger.
    func actualFrame(_ window: NSWindow) -> NSRect {
        let area = (window.screen ?? NSScreen.main!).visibleFrame
        guard videoSize.width <= area.width, videoSize.height <= area.height else {
            return fittedFrame(window, fraction: 1)
        }
        return centered(videoSize, in: area)
    }

    // Scales the window around its center, kept inside the screen and above the minimum size.
    func scaleWindow(by factor: CGFloat) {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        let area = (window.screen ?? NSScreen.main!).visibleFrame
        var size = NSSize(width: window.frame.width * factor, height: window.frame.height * factor)
        let limit = min(area.width / size.width, area.height / size.height, 1)
        size = NSSize(width: size.width * limit, height: size.height * limit)
        guard size.width >= window.contentMinSize.width, size.height >= window.contentMinSize.height else { return }
        let frame = NSRect(x: window.frame.midX - size.width / 2, y: window.frame.midY - size.height / 2,
                           width: size.width, height: size.height)
        window.setFrame(frame.constrained(to: area), display: true, animate: true)
    }

    private func centered(_ size: NSSize, in area: NSRect) -> NSRect {
        NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
    }

    private func displaySize(of asset: AVURLAsset) async -> CGSize {
        let fallback = CGSize(width: 16, height: 9)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let (natural, transform) = try? await track.load(.naturalSize, .preferredTransform)
        else { return fallback }
        let s = natural.applying(transform)
        let size = CGSize(width: abs(s.width), height: abs(s.height))
        return size.width > 0 && size.height > 0 ? size : fallback
    }

    // MARK: Title bar fade

    // Title bar and traffic lights fade with the player controls, as in QuickTime Player:
    // shown on mouse movement, hidden after 2.5 s idle while playing or when the mouse leaves.
    func showChrome() {
        setChrome(visible: true)
        chromeTimer?.invalidate()
        chromeTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let player = self.player, player.rate > 0 else { return }
                self.setChrome(visible: false)
            }
        }
    }

    func setChrome(visible: Bool) {
        guard let window, !window.styleMask.contains(.fullScreen),
              let titlebar = window.standardWindowButton(.closeButton)?.superview
        else { return }
        let show = visible || !Prefs.defaults.bool(forKey: Prefs.autoHide)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            titlebar.animator().alphaValue = show ? 1 : 0
        }
    }

    // F toggles full screen; Esc leaves full screen first, then closes. Other playback
    // keys are menu key equivalents (Menu.swift).
    private func handleKey(_ event: NSEvent) -> Bool {
        guard let window, window.isKeyWindow, !event.isARepeat else { return false }
        let mods = event.modifierFlags.intersection([.shift, .control, .option, .command])
        guard mods.isEmpty else { return false }
        if event.charactersIgnoringModifiers?.lowercased() == "f" {
            window.toggleFullScreen(nil)
            return true
        }
        if event.keyCode == 53 {  // Esc
            if window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            } else {
                window.close()
            }
            return true
        }
        return false
    }
}

private extension NSRect {
    // Moves the rect inside `area` without resizing it.
    func constrained(to area: NSRect) -> NSRect {
        var r = self
        r.origin.x = Swift.min(Swift.max(r.minX, area.minX), area.maxX - r.width)
        r.origin.y = Swift.min(Swift.max(r.minY, area.minY), area.maxY - r.height)
        return r
    }
}
