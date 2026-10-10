import AppKit
import MediaToolbox

// Opt in to third-party Media Extensions (e.g. QLVideo's Matroska/WebM readers).
MTRegisterProfessionalVideoWorkflowFormatReaders()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
