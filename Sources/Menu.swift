// Main menu and the playback, view and audio actions behind it.
// Items without a modifier key (Space, arrows, comma, period, M) are enabled only while
// the video window is key, so the same keys still work in other windows and dialogs.
import AVFoundation
import AVKit
import AppKit

private let speeds: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]

private func key(_ scalar: Int) -> String { String(Character(UnicodeScalar(scalar)!)) }

private func item(_ title: String, _ action: Selector?, _ key: String = "",
                  _ mods: NSEvent.ModifierFlags = [.command], tag: Int = 0) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.keyEquivalentModifierMask = mods
    item.tag = tag
    return item
}

private func submenu(_ title: String, _ items: [NSMenuItem], delegate: NSMenuDelegate? = nil) -> NSMenuItem {
    let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    let menu = NSMenu(title: title)
    items.forEach { menu.addItem($0) }
    menu.delegate = delegate
    parent.submenu = menu
    return parent
}

extension AppDelegate: NSMenuDelegate, NSMenuItemValidation {
    func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let services = submenu("Services", [])
        NSApp.servicesMenu = services.submenu
        main.addItem(submenu("QuickPlay", [
            item("About QuickPlay", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Settings…", #selector(showSettings), ","),
            .separator(),
            services,
            .separator(),
            item("Hide QuickPlay", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit QuickPlay", #selector(NSApplication.terminate(_:)), "q"),
        ]))

        let recent = submenu("Open Recent", [], delegate: self)
        recent.submenu!.identifier = .init("recent")
        let file = submenu("File", [
            item("Open…", #selector(openDocument(_:)), "o"),
            recent,
            .separator(),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
            item("Save As…", #selector(saveCopyAs), "s", [.command, .shift]),
            submenu("Export As", [
                item("1080p…", #selector(exportVideo(_:)), tag: 1080),
                item("720p…", #selector(exportVideo(_:)), tag: 720),
                item("480p…", #selector(exportVideo(_:)), tag: 480),
                item("Audio Only…", #selector(exportVideo(_:)), tag: 0),
            ]),
            item("Save Frame As…", #selector(saveFrame), "s", [.command, .option]),
            .separator(),
            item("Show in Finder", #selector(showInFinder), "r", [.command, .shift]),
            item("Move to Trash", #selector(moveToTrash), key(NSBackspaceCharacter)),
            .separator(),
            NSMenuItem(title: "Share", action: nil, keyEquivalent: ""),
        ], delegate: self)
        file.submenu!.identifier = .init("file")
        main.addItem(file)

        // Cut/Copy/Paste go to the first responder: text fields handle them in dialogs,
        // and Copy reaches AppDelegate.copy(_:) (the current frame) in the video window.
        main.addItem(submenu("Edit", [
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("Copy Frame", #selector(copyFrame), "c", [.command, .option]),
        ]))

        let speedItems = speeds.map { item(String(format: "%g×", $0), #selector(setSpeed(_:)), tag: Int($0 * 100)) }
        main.addItem(submenu("Playback", [
            item("Play/Pause", #selector(togglePlay), " ", []),
            .separator(),
            item("Jump Forward 5 s", #selector(jumpForward), key(NSRightArrowFunctionKey), []),
            item("Jump Back 5 s", #selector(jumpBack), key(NSLeftArrowFunctionKey), []),
            item("Next Frame", #selector(nextFrame), ".", []),
            item("Previous Frame", #selector(previousFrame), ",", []),
            item("Jump to Beginning", #selector(jumpToBeginning), key(NSLeftArrowFunctionKey), [.option]),
            item("Jump to…", #selector(jumpTo), "j"),
            .separator(),
            submenu("Speed", speedItems),
            item("Faster", #selector(faster), "]"),
            item("Slower", #selector(slower), "["),
            item("Normal Speed", #selector(normalSpeed), "0"),
            .separator(),
            item("Loop", #selector(toggleLoop), "l", [.command, .option]),
        ]))

        main.addItem(submenu("Video", [
            item("Actual Size", #selector(actualSize), "1"),
            item("Fit to Screen", #selector(fitToScreen), "3"),
            item("Bigger", #selector(bigger), "="),
            item("Smaller", #selector(smaller), "-"),
            .separator(),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
            item("Float on Top", #selector(toggleFloat), "t", [.command, .option]),
        ]))

        let audioTracks = submenu("Audio Track", [], delegate: self)
        audioTracks.submenu!.identifier = .init("audio")
        main.addItem(submenu("Audio", [
            item("Volume Up", #selector(volumeUp), key(NSUpArrowFunctionKey), []),
            item("Volume Down", #selector(volumeDown), key(NSDownArrowFunctionKey), []),
            item("Mute", #selector(toggleMute), "m", []),
            .separator(),
            audioTracks,
        ]))

        let subtitles = submenu("Subtitles", [], delegate: self)
        subtitles.submenu!.identifier = .init("subtitles")
        main.addItem(subtitles)

        let window = submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
        ])
        NSApp.windowsMenu = window.submenu
        main.addItem(window)

        let help = submenu("Help", [item("QuickPlay Help", #selector(showHelp), "?")])
        NSApp.helpMenu = help.submenu
        main.addItem(help)
        return main
    }

    // MARK: Dynamic menus

    func menuNeedsUpdate(_ menu: NSMenu) {
        switch menu.identifier?.rawValue {
        case "recent":
            menu.removeAllItems()
            for url in Prefs.recentFiles where FileManager.default.fileExists(atPath: url.path) {
                let entry = item(url.lastPathComponent, #selector(openRecent(_:)), "", [])
                entry.representedObject = url
                entry.image = NSWorkspace.shared.icon(forFile: url.path)
                entry.image?.size = NSSize(width: 16, height: 16)
                menu.addItem(entry)
            }
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            menu.addItem(item("Clear Menu", #selector(clearRecent), "", []))
        case "file":
            // Rebuild the Share entry for the current file.
            guard let index = menu.items.firstIndex(where: { $0.title == "Share" }) else { return }
            menu.removeItem(at: index)
            let share = currentURL.map { NSSharingServicePicker(items: [$0]).standardShareMenuItem }
                ?? NSMenuItem(title: "Share", action: nil, keyEquivalent: "")
            share.title = "Share"
            menu.insertItem(share, at: index)
        case "audio":
            fillSelectionMenu(menu, group: audioGroup, allowsOff: false)
        case "subtitles":
            fillSelectionMenu(menu, group: subtitleGroup, allowsOff: true)
        default:
            break
        }
    }

    private func fillSelectionMenu(_ menu: NSMenu, group: AVMediaSelectionGroup?, allowsOff: Bool) {
        menu.removeAllItems()
        guard let group, let current = player?.currentItem else {
            menu.addItem(item("None", nil, "", []))
            return
        }
        let selected = current.currentMediaSelection.selectedMediaOption(in: group)
        if allowsOff {
            let off = item("Off", #selector(selectMediaOption(_:)), "", [])
            off.representedObject = group
            off.state = selected == nil ? .on : .off
            menu.addItem(off)
            menu.addItem(.separator())
        }
        for option in group.options {
            let entry = item(option.displayName, #selector(selectMediaOption(_:)), "", [])
            entry.representedObject = (group, option)
            entry.state = option == selected ? .on : .off
            menu.addItem(entry)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let hasVideo = window != nil && player != nil
        switch menuItem.action {
        case #selector(NSText.copy(_:)):
            return hasVideo && window?.isKeyWindow == true
        case #selector(openDocument(_:)), #selector(showSettings), #selector(showHelp),
             #selector(openRecent(_:)), #selector(clearRecent):
            return true
        case #selector(toggleLoop):
            menuItem.state = Prefs.defaults.bool(forKey: Prefs.loop) ? .on : .off
            return true
        case #selector(setSpeed(_:)):
            menuItem.state = Int((player?.defaultRate ?? 1) * 100) == menuItem.tag ? .on : .off
            return hasVideo
        case #selector(toggleFloat):
            menuItem.state = window?.level == .floating ? .on : .off
            return hasVideo
        case #selector(toggleMute):
            menuItem.state = player?.isMuted == true ? .on : .off
            return hasVideo && window?.isKeyWindow == true
        case #selector(selectMediaOption(_:)):
            return hasVideo
        case #selector(exportVideo(_:)):
            return hasVideo && (menuItem.tag != 0 || hasAudio)
        default:
            guard hasVideo else { return false }
            // Bare keys act only while the video window is key.
            return !menuItem.keyEquivalentModifierMask.isEmpty || menuItem.keyEquivalent.isEmpty
                || window?.isKeyWindow == true
        }
    }

    // MARK: File

    // Modal panels run after the menu has closed: starting the out-of-process Open panel
    // inside menu tracking raises NSInvalidArgumentException and the panel fails to start.
    // Default mode only: the main queue also drains during menu tracking, so it is too early.
    func afterMenuCloses(_ body: @escaping () -> Void) {
        RunLoop.main.perform(inModes: [.default], block: body)
    }

    @objc func openDocument(_ sender: Any?) {
        openPanelShown = true
        afterMenuCloses { self.runOpenPanel() }
    }

    private func runOpenPanel() {
        defer { openPanelShown = false }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .audiovisualContent]
        panel.allowsMultipleSelection = false
        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url {
            open(url)
        } else if window == nil, openRequests == 0 {
            NSApp.terminate(nil)
        }
    }

    @objc func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        open(url)
    }

    @objc func clearRecent() {
        Prefs.clearRecent()
        NSDocumentController.shared.clearRecentDocuments(nil)
    }

    // MARK: Playback

    @objc func togglePlay() {
        guard let player else { return }
        player.rate == 0 ? player.play() : player.pause()
    }

    @objc func jumpForward() { jump(by: 5) }
    @objc func jumpBack() { jump(by: -5) }

    private func jump(by seconds: Double) {
        guard let player else { return }
        let target = CMTimeAdd(player.currentTime(), CMTime(seconds: seconds, preferredTimescale: 600))
        player.seek(to: CMTimeMaximum(target, .zero))
    }

    @objc func nextFrame() { step(1) }
    @objc func previousFrame() { step(-1) }

    private func step(_ count: Int) {
        player?.pause()
        player?.currentItem?.step(byCount: count)
    }

    @objc func jumpToBeginning() {
        player?.seek(to: .zero)
    }

    @objc func jumpTo() {
        afterMenuCloses { self.runJumpTo() }
    }

    private func runJumpTo() {
        guard let player else { return }
        let alert = NSAlert()
        alert.messageText = "Jump to"
        alert.informativeText = "Enter a time as h:mm:ss, m:ss or seconds."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = Self.format(player.currentTime().seconds)
        alert.accessoryView = field
        alert.addButton(withTitle: "Jump")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let seconds = Self.parse(field.stringValue) else {
            NSSound.beep()
            return
        }
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let s = Int(seconds)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    static func parse(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":").map { Double($0) }
        guard (1...3).contains(parts.count), parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        return parts.reduce(0) { $0 * 60 + $1! }
    }

    @objc func setSpeed(_ sender: NSMenuItem) {
        applySpeed(Float(sender.tag) / 100)
    }

    @objc func faster() {
        let current = player?.defaultRate ?? 1
        applySpeed(speeds.first { $0 > current } ?? current)
    }

    @objc func slower() {
        let current = player?.defaultRate ?? 1
        applySpeed(speeds.last { $0 < current } ?? current)
    }

    @objc func normalSpeed() { applySpeed(1) }

    // defaultRate is the rate play() uses; a paused video stays paused.
    private func applySpeed(_ rate: Float) {
        guard let player else { return }
        player.defaultRate = rate
        if player.rate != 0 { player.rate = rate }
    }

    @objc func toggleLoop() {
        Prefs.defaults.set(!Prefs.defaults.bool(forKey: Prefs.loop), forKey: Prefs.loop)
    }

    // MARK: Video

    @objc func actualSize() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        window.setFrame(actualFrame(window), display: true, animate: true)
    }

    @objc func fitToScreen() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        window.setFrame(fittedFrame(window, fraction: 1), display: true, animate: true)
    }

    @objc func bigger() { scaleWindow(by: 1.25) }
    @objc func smaller() { scaleWindow(by: 0.8) }

    @objc func toggleFloat() {
        guard let window else { return }
        window.level = window.level == .floating ? .normal : .floating
    }

    // MARK: Audio and subtitles

    @objc func volumeUp() { changeVolume(by: 0.1) }
    @objc func volumeDown() { changeVolume(by: -0.1) }

    private func changeVolume(by delta: Float) {
        guard let player else { return }
        player.isMuted = false
        player.volume = min(max(player.volume + delta, 0), 1)
    }

    @objc func toggleMute() {
        player?.isMuted.toggle()
    }

    @objc func selectMediaOption(_ sender: NSMenuItem) {
        guard let item = player?.currentItem else { return }
        if let (group, option) = sender.representedObject as? (AVMediaSelectionGroup, AVMediaSelectionOption) {
            item.select(option, in: group)
        } else if let group = sender.representedObject as? AVMediaSelectionGroup {
            item.select(nil, in: group)
        }
    }

    // MARK: Help

    @objc func showHelp() {
        afterMenuCloses { self.runHelp() }
    }

    private func runHelp() {
        let alert = NSAlert()
        alert.messageText = "QuickPlay keyboard shortcuts"
        alert.informativeText = """
            Space\tPlay / pause
            ← / →\tJump back / forward 5 s
            , / .\tPrevious / next frame
            ⌥←\tJump to beginning
            ⌘J\tJump to a time
            ⌘[ / ⌘]\tSlower / faster, ⌘0 normal speed
            ↑ / ↓\tVolume, M mute
            F or double-click\tFull screen
            Esc\tLeave full screen, then close
            ⌘1 / ⌘3\tActual size / fit to screen
            ⌘C\tCopy the current frame
            """
        alert.runModal()
    }
}
