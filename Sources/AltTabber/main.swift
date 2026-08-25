import AppKit

// Top-level entry runs synchronously on the main thread at process start, so it
// is safe to assume main-actor isolation for our @MainActor AppDelegate.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Agent app: no Dock icon, no menu bar — lives in the status bar only.
    app.setActivationPolicy(.accessory)
    app.run()
}
