import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let controller = SwitcherController()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        // Prompt for Accessibility on first launch — required for the event tap.
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)

        if !controller.start() {
            // Tap creation failed — almost always missing Accessibility permission.
            presentPermissionAlert(accessibilityTrusted: trusted)
        }

        // Poll until permission is granted, then (re)install the tap.
        if !trusted {
            waitForAccessibilityThenStart()
        }
    }

    // MARK: - Permission recovery

    private func waitForAccessibilityThenStart() {
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if AXIsProcessTrusted() {
                timer.invalidate()
                MainActor.assumeIsolated {
                    _ = self.controller.start()
                    self.refreshStatusMenu(trusted: true)
                }
            }
        }
    }

    private func presentPermissionAlert(accessibilityTrusted: Bool) {
        let alert = NSAlert()
        alert.messageText = "AltTabber a besoin d'autorisations"
        alert.informativeText = """
        Pour intercepter ⌥+Tab et basculer entre fenêtres, active :

        • Accessibilité — pour le raccourci et le focus des fenêtres
        • Enregistrement de l'écran — pour les vignettes des fenêtres

        Réglages Système → Confidentialité et sécurité.
        AltTabber s'active automatiquement dès l'autorisation accordée.
        """
        alert.addButton(withTitle: "Ouvrir Accessibilité")
        alert.addButton(withTitle: "Ouvrir Enregistrement de l'écran")
        alert.addButton(withTitle: "Plus tard")
        switch alert.runModal() {
        case .alertFirstButtonReturn: Self.openAccessibilitySettings()
        case .alertSecondButtonReturn: Self.openScreenRecordingSettings()
        default: break
        }
    }

    // MARK: - Status bar menu

    private func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "square.stack.3d.up.fill",
                accessibilityDescription: "AltTabber"
            )
            image?.isTemplate = true
            button.image = image
        }
        self.statusItem = statusItem
        refreshStatusMenu(trusted: AXIsProcessTrusted())
    }

    private func refreshStatusMenu(trusted: Bool) {
        let menu = NSMenu()

        let header = NSMenuItem(title: "AltTabber — ⌥ + Tab", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let status = NSMenuItem(
            title: trusted ? "✓ Accessibilité accordée" : "⚠︎ Accessibilité requise",
            action: nil, keyEquivalent: ""
        )
        status.isEnabled = false
        menu.addItem(status)

        menu.addItem(.separator())
        let prefs = NSMenuItem(title: "Réglages…", action: #selector(openPreferences), keyEquivalent: ",")
        menu.addItem(prefs)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Autorisation Accessibilité…",
            action: #selector(openAccessibility), keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: "Autorisation Enregistrement de l'écran…",
            action: #selector(openScreenRecording), keyEquivalent: ""
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quitter AltTabber", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items { item.target = self }
        statusItem?.menu = menu
    }

    // MARK: - Actions

    @objc private func openPreferences() { PreferencesWindowController.shared.show() }
    @objc private func openAccessibility() { Self.openAccessibilitySettings() }
    @objc private func openScreenRecording() { Self.openScreenRecordingSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    private static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }
    private static func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }
    private static func open(_ urlString: String) {
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }
}
