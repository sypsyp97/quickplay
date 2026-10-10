// File menu actions: save a copy, export, frame grabs, Finder and Trash.
import AVFoundation
import AppKit
import UniformTypeIdentifiers

extension AppDelegate {
    // Writes through `write` into a scratch file next to `target`, then swaps it in, so a
    // failure or cancel never touches an existing file. Refuses to overwrite the open video.
    func writeSafely(to target: URL, source: URL, write: (URL, @escaping (Error?) -> Void) -> Void,
                     done: @escaping (Error?) -> Void) {
        if Self.sameFile(target, source) {
            return done(CocoaError(.fileWriteNoPermission, userInfo: [
                NSLocalizedDescriptionKey: "Choose a different name; this would replace the video that is open."]))
        }
        let fm = FileManager.default
        let scratchDir: URL
        do {
            scratchDir = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                    appropriateFor: target, create: true)
        } catch { return done(error) }
        let scratch = scratchDir.appendingPathComponent(target.lastPathComponent)
        write(scratch) { error in
            defer { try? fm.removeItem(at: scratchDir) }
            if let error { return done(error) }
            do {
                if fm.fileExists(atPath: target.path) {
                    _ = try fm.replaceItemAt(target, withItemAt: scratch)
                } else {
                    try fm.moveItem(at: scratch, to: target)
                }
                done(nil)
            } catch { done(error) }
        }
    }

    static func sameFile(_ a: URL, _ b: URL) -> Bool {
        let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard let ia = try? a.resourceValues(forKeys: key).fileResourceIdentifier,
              let ib = try? b.resourceValues(forKeys: key).fileResourceIdentifier
        else { return a.standardizedFileURL.path == b.standardizedFileURL.path }
        return ia.isEqual(ib)
    }

    @objc func copy(_ sender: Any?) {
        copyFrame()
    }

    // Save panels are out-of-process like the Open panel: start them after the menu closes.
    @objc func saveCopyAs() {
        afterMenuCloses { self.presentSaveCopy() }
    }

    private func presentSaveCopy() {
        guard let source = currentURL, let window else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = source.lastPathComponent
        panel.directoryURL = source.deletingLastPathComponent()
        if let type = UTType(filenameExtension: source.pathExtension) { panel.allowedContentTypes = [type] }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let target = panel.url else { return }
            self.writeSafely(to: target, source: source, write: { scratch, finish in
                finish(Result { try FileManager.default.copyItem(at: source, to: scratch) }.failure)
            }, done: { error in
                if let error { self.showError(error.localizedDescription) }
            })
        }
    }

    // Tag 1080 / 720 / 480 picks a video preset; tag 0 exports audio only.
    @objc func exportVideo(_ sender: NSMenuItem) {
        afterMenuCloses { self.presentExport(sender) }
    }

    private func presentExport(_ sender: NSMenuItem) {
        guard let source = currentURL, let window, let asset = player?.currentItem?.asset else { return }
        let audioOnly = sender.tag == 0
        let preset = switch sender.tag {
        case 1080: AVAssetExportPreset1920x1080
        case 720: AVAssetExportPreset1280x720
        case 480: AVAssetExportPreset640x480
        default: AVAssetExportPresetAppleM4A
        }
        let fileType: AVFileType = audioOnly ? .m4a : .mov
        Task { @MainActor in
            guard await AVAssetExportSession.compatibility(ofExportPreset: preset, with: asset, outputFileType: fileType) else {
                return self.showError(audioOnly ? "This video has no audio to export."
                                                : "This video cannot be exported as \(sender.title.dropLast()).")
            }
            // The check awaited; a menu may be open again by now.
            self.afterMenuCloses {
                self.presentExportPanel(source: source, window: window, asset: asset, preset: preset,
                                        fileType: fileType, audioOnly: audioOnly, tag: sender.tag, title: sender.title)
            }
        }
    }

    private func presentExportPanel(source: URL, window: NSWindow, asset: AVAsset, preset: String,
                                    fileType: AVFileType, audioOnly: Bool, tag: Int, title: String) {
        let suffix = audioOnly ? "" : " \(tag)p"
        let panel = NSSavePanel()
        panel.nameFieldStringValue = source.deletingPathExtension().lastPathComponent + suffix
        panel.directoryURL = source.deletingLastPathComponent()
        panel.allowedContentTypes = [audioOnly ? .mpeg4Audio : .quickTimeMovie]
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let target = panel.url else { return }
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
                self.showError("This video cannot be exported with the \(title.dropLast()) preset.")
                return
            }
            session.outputFileType = fileType
            self.writeSafely(to: target, source: source, write: { scratch, finish in
                session.outputURL = scratch
                self.runExport(session, title: "Exporting \(target.lastPathComponent)", finish: finish)
            }, done: { error in
                guard let error, (error as? CocoaError)?.code != .userCancelled else { return }
                self.showError(error.localizedDescription)
            })
        }
    }

    // Shows a progress sheet until the export ends; Cancel stops it.
    private func runExport(_ session: AVAssetExportSession, title: String, finish: @escaping (Error?) -> Void) {
        guard let window else { return finish(CocoaError(.userCancelled)) }
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 110),
                             styleMask: [.titled], backing: .buffered, defer: false)
        let label = NSTextField(labelWithString: title)
        label.lineBreakMode = .byTruncatingMiddle
        label.frame = NSRect(x: 20, y: 70, width: 320, height: 20)
        let bar = NSProgressIndicator(frame: NSRect(x: 20, y: 46, width: 320, height: 16))
        bar.isIndeterminate = false
        bar.maxValue = 1
        let cancel = NSButton(title: "Cancel", target: nil, action: nil)
        cancel.frame = NSRect(x: 260, y: 10, width: 80, height: 28)
        cancel.bezelStyle = .push
        let canceller = ExportCanceller(session)
        cancel.target = canceller
        cancel.action = #selector(ExportCanceller.cancel)
        [label, bar, cancel].forEach { sheet.contentView!.addSubview($0) }
        window.beginSheet(sheet)

        let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            bar.doubleValue = Double(session.progress)
        }
        session.exportAsynchronously {
            DispatchQueue.main.async {
                timer.invalidate()
                _ = canceller
                window.endSheet(sheet)
                switch session.status {
                case .completed:
                    finish(nil)
                case .cancelled:
                    finish(CocoaError(.userCancelled))
                default:
                    finish(session.error ?? CocoaError(.fileWriteUnknown))
                }
            }
        }
    }

    static let ciContext = CIContext()

    @objc func copyFrame() {
        grabFrame { image in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
        }
    }

    @objc func saveFrame() {
        afterMenuCloses { self.presentSaveFrame() }
    }

    private func presentSaveFrame() {
        guard let source = currentURL, let window, let player else { return }
        let stamp = Self.format(player.currentTime().seconds).replacingOccurrences(of: ":", with: ".")
        grabFrame { image in self.afterMenuCloses {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "\(source.deletingPathExtension().lastPathComponent) \(stamp).png"
            panel.directoryURL = source.deletingLastPathComponent()
            panel.allowedContentTypes = [.png]
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let target = panel.url else { return }
                guard let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
                else { return self.showError("Could not encode the frame.") }
                do { try png.write(to: target) } catch { self.showError(error.localizedDescription) }
            }
        } }
    }

    // Decodes the exact frame on screen at full resolution.
    private func grabFrame(_ done: @escaping (NSImage) -> Void) {
        guard let player, let asset = player.currentItem?.asset else { return }
        let time = player.currentTime()
        // The displayed frame first: decoding by time can land on another frame for
        // formats read through Media Extensions (measured: an MKV returned 0 s for 3 s).
        if let output = videoOutput,
           let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
            let image = CIImage(cvPixelBuffer: buffer)
            if let cg = Self.ciContext.createCGImage(image, from: image.extent) {
                lastFrame = (time, cg)
            }
        }
        // Still the same picture when less than one frame has passed since the last grab.
        if let lastFrame, abs(CMTimeGetSeconds(CMTimeSubtract(time, lastFrame.time))) < frameDuration {
            let cg = lastFrame.image
            return done(NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        Task { @MainActor in
            do {
                let (image, _) = try await generator.image(at: time)
                done(NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
            } catch {
                self.showError("Could not read this frame: \(error.localizedDescription)")
            }
        }
    }

    @objc func showInFinder() {
        guard let currentURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([currentURL])
    }

    // Like Finder's Cmd-Delete: no confirmation, the file stays recoverable from the Trash.
    @objc func moveToTrash() {
        guard let url = currentURL, let window else { return }
        player?.pause()
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            Prefs.setPosition(nil, for: url)
            // Forget the file so closing does not save its position again.
            currentURL = nil
            window.close()
        } catch {
            self.showError(error.localizedDescription)
        }
    }

    // Deferred like the panels: errors can surface while a menu is open.
    func showError(_ message: String) {
        afterMenuCloses {
            let alert = NSAlert()
            alert.messageText = message
            if let window = self.window, window.isVisible { alert.beginSheetModal(for: window) } else { alert.runModal() }
        }
    }
}

private final class ExportCanceller: NSObject {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
    @objc func cancel() { session.cancelExport() }
}

private extension Result where Failure == Error {
    var failure: Error? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
