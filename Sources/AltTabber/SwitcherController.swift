import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// Owns the overlay + event tap and drives the whole switch interaction.
///
/// Two activation styles (see AppSettings):
///  • hold      — hold the modifier, Tab to advance, release to commit.
///  • stayOpen  — tap modifier+Tab, release; panel stays. Tab / arrows / type to
///                search, Enter or click to commit, Esc to cancel.
@MainActor
final class SwitcherController {

    private let model = SwitcherModel()
    private lazy var panel = SwitcherPanel(model: model)
    private let settings = AppSettings.shared

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var mouseMonitor: Any?

    // Layout constants — must mirror SwitcherView.
    private let gridSpacing: CGFloat = 12
    private let innerPad: CGFloat = 18
    private let outerPad: CGFloat = 24
    private let vStackSpacing: CGFloat = 12
    private let searchBarHeight: CGFloat = 40
    private let emptyStateSize = NSSize(width: 360, height: 160)

    /// Monotonic token so late thumbnails from a previous invocation are ignored.
    private var sessionToken = 0

    init() {
        model.onActivate = { [weak self] index in self?.activate(index) }
        model.onHover = { [weak self] index in
            guard let self, self.model.selectedIndex != index else { return }
            self.model.selectedIndex = index
        }
    }

    // MARK: - Event tap lifecycle

    /// Installs the CGEvent tap. Returns false if the tap could not be created
    /// (usually means Accessibility permission is missing).
    @discardableResult
    func start() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<SwitcherController>.fromOpaque(refcon).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                controller.reenableTap()
                return Unmanaged.passUnretained(event)
            }

            return MainActor.assumeIsolated {
                controller.handle(type: type, event: event)
            }
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: refcon
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        return true
    }

    private func reenableTap() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        let flags = event.flags
        let modifierDown = flags.contains(settings.modifier.cgFlag)

        // Modifier release: commit only in "hold" style; "stayOpen" keeps it up.
        if type == .flagsChanged {
            if model.visible && !modifierDown && settings.activationStyle == .hold {
                commit()
            }
            return pass
        }

        guard type == .keyDown else { return pass }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let shift = flags.contains(.maskShift)

        // modifier + Tab — the primary trigger.
        if keyCode == kVK_Tab && modifierDown {
            if model.visible {
                model.step(shift ? -1 : 1)
            } else {
                show()
                model.step(shift ? -1 : 1)
            }
            return nil
        }

        guard model.visible else { return pass }

        // Plain Tab while open (no modifier held) — enables "stayOpen" spamming.
        if keyCode == kVK_Tab {
            model.step(shift ? -1 : 1)
            return nil
        }

        switch keyCode {
        case kVK_ANSI_Grave where modifierDown:    // modifier + `  → reverse
            model.step(shift ? 1 : -1)
            return nil
        case kVK_RightArrow:
            model.step(1); return nil
        case kVK_LeftArrow:
            model.step(-1); return nil
        case kVK_DownArrow:
            model.step(model.columns); return nil
        case kVK_UpArrow:
            model.step(-model.columns); return nil
        case kVK_Return, kVK_ANSI_KeypadEnter:
            commit(); return nil
        case kVK_Escape:
            cancel(); return nil
        case kVK_Delete:
            backspaceSearch(); return nil
        default:
            // Type-to-search (only when the modifier isn't held).
            if !modifierDown, let character = printableCharacter(from: event) {
                appendSearch(character)
            }
            // Swallow everything else so it doesn't leak to the app below.
            return nil
        }
    }

    // MARK: - Search

    private func appendSearch(_ character: String) {
        model.searchText += character
        model.selectedIndex = 0
        model.applyFilter()
        panel.resize(to: computeSize())
    }

    private func backspaceSearch() {
        guard !model.searchText.isEmpty else { return }
        model.searchText.removeLast()
        model.selectedIndex = 0
        model.applyFilter()
        panel.resize(to: computeSize())
    }

    /// Extracts a printable character for the search field, rejecting control
    /// characters and function/arrow keys.
    private func printableCharacter(from event: CGEvent) -> String? {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &buffer)
        guard length > 0 else { return nil }
        let string = String(utf16CodeUnits: buffer, count: length)
        guard let scalar = string.unicodeScalars.first else { return nil }
        if scalar.value < 0x20 { return nil }                       // control chars
        if (0xF700...0xF8FF).contains(scalar.value) { return nil }  // function keys
        return string
    }

    // MARK: - Presentation

    private func show() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windows = WindowManager.listWindows(
            excludingPID: ownPID,
            includeMinimized: settings.includeMinimized,
            allSpaces: settings.allSpaces
        )
        guard !windows.isEmpty else { return }

        model.windows = windows
        model.searchText = ""
        model.selectedIndex = 0
        model.thumbnails = [:]
        model.cardWidth = settings.thumbnailSize.cardWidth
        model.cardHeight = settings.thumbnailSize.cardHeight
        model.showTitles = settings.showTitles
        model.animationsEnabled = settings.animations
        model.applyFilter()

        panel.appearance = settings.appearance.nsAppearance
        model.visible = true
        panel.present(sizedTo: computeSize(), animated: settings.animations)

        if settings.activationStyle == .stayOpen { startMouseMonitor() }
        captureThumbnails(for: windows)
    }

    /// Computes the panel size for the current filtered set and updates columns.
    private func computeSize() -> NSSize {
        let hasSearch = !model.searchText.isEmpty
        let searchExtra: CGFloat = hasSearch ? (searchBarHeight + vStackSpacing) : 0

        let contentW: CGFloat
        let contentH: CGFloat
        if model.filtered.isEmpty {
            contentW = emptyStateSize.width
            contentH = emptyStateSize.height
        } else {
            let cols = min(model.filtered.count, max(1, settings.maxColumns))
            model.columns = cols
            let rows = Int(ceil(Double(model.filtered.count) / Double(cols)))
            contentW = CGFloat(cols) * model.cardWidth + CGFloat(cols - 1) * gridSpacing
            contentH = CGFloat(rows) * model.cardHeight + CGFloat(rows - 1) * gridSpacing
        }

        return NSSize(
            width: contentW + 2 * innerPad + 2 * outerPad,
            height: contentH + searchExtra + 2 * innerPad + 2 * outerPad
        )
    }

    private func activate(_ index: Int) {
        guard model.visible else { return }
        model.selectedIndex = index
        commit()
    }

    private func commit() {
        guard model.visible else { return }
        let target = model.selectedWindow
        teardown()
        if let target { WindowManager.focus(target) }
    }

    private func cancel() {
        guard model.visible else { return }
        teardown()
    }

    private func teardown() {
        model.visible = false
        model.searchText = ""
        stopMouseMonitor()
        panel.dismiss()
    }

    // MARK: - Mouse (click-outside to cancel, stayOpen only)

    private func startMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.cancel() }
        }
    }

    private func stopMouseMonitor() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    // MARK: - Thumbnails

    private func captureThumbnails(for windows: [WindowInfo]) {
        sessionToken &+= 1
        let token = sessionToken
        let ids = Set(windows.map { $0.id })

        let maxDim = settings.thumbnailSize.maxThumbDimension
        Task { [weak self] in
            await WindowManager.captureThumbnails(for: windows, maxDimension: maxDim) { id, image in
                guard let self else { return }
                guard self.sessionToken == token, self.model.visible, ids.contains(id) else { return }
                self.model.thumbnails[id] = image
            }
        }
    }
}
