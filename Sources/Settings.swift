// Settings window (Cmd-,).
import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct SettingsView: View {
    @AppStorage(Prefs.resume) private var resume = true
    @AppStorage(Prefs.loop) private var loop = false
    @AppStorage(Prefs.openSize) private var openSize = "fit"
    @AppStorage(Prefs.autoHide) private var autoHide = true
    @State private var defaultStatus = ""

    var body: some View {
        Form {
            Section("Playback") {
                Toggle("Resume where I left off", isOn: $resume)
                Toggle("Loop videos", isOn: $loop)
            }
            Section("Window") {
                Picker("Window size when opening", selection: $openSize) {
                    Text("Fit to screen (80 %)").tag("fit")
                    Text("Actual size").tag("actual")
                }
                Toggle("Hide the title bar with the playback controls", isOn: $autoHide)
            }
            Section("Default player") {
                HStack {
                    Button("Open videos with QuickPlay") { makeDefault() }
                    Text(defaultStatus).foregroundStyle(.secondary)
                }
                Text("Applies to MP4, MOV, MKV, WebM, AVI and other video formats.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
    }

    private func makeDefault() {
        let app = Bundle.main.bundleURL
        let types = Prefs.videoTypes.compactMap { UTType($0) }
        defaultStatus = "Working…"
        Task { @MainActor in
            var failed = 0
            for type in types {
                do { try await NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type) } catch { failed += 1 }
            }
            defaultStatus = failed == 0 ? "Done" : "\(failed) of \(types.count) formats not changed"
        }
    }
}

extension AppDelegate {
    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "QuickPlay Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow!.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
