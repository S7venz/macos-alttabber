import AppKit
import SwiftUI

/// Hosting view that accepts clicks even while the panel isn't the key window —
/// otherwise macOS swallows the first click on a non-active panel.
private final class ClickableHostingView: NSHostingView<SwitcherView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    required init(rootView: SwitcherView) { super.init(rootView: rootView) }
    required init?(coder: NSCoder) { super.init(coder: coder) }
}

/// A borderless, non-activating floating panel that hosts the SwiftUI overlay.
/// It never becomes key, so the app underneath keeps its focus until we commit.
final class SwitcherPanel: NSPanel {

    init(model: SwitcherModel) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        isMovableByWindowBackground = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false            // the SwiftUI card draws its own shadow
        hidesOnDeactivate = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true   // needed for hover-to-highlight

        let hosting = ClickableHostingView(rootView: SwitcherView(model: model))
        hosting.frame = contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Size the panel to the content and center it on the active screen, then
    /// show it without stealing focus.
    func present(sizedTo contentSize: NSSize, animated: Bool = true) {
        resize(to: contentSize)
        orderFrontRegardless()
        guard animated else { alphaValue = 1; return }
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.11
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    /// Recenter + resize (used live while filtering via the search bar).
    func resize(to contentSize: NSSize) {
        let frame = Self.activeScreen().visibleFrame
        let origin = NSPoint(
            x: frame.midX - contentSize.width / 2,
            y: frame.midY - contentSize.height / 2
        )
        setFrame(NSRect(origin: origin, size: contentSize), display: true)
    }

    func dismiss() {
        orderOut(nil)
        alphaValue = 0
    }

    private static func activeScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first!
    }
}
