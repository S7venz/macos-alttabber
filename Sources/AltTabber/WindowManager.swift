import AppKit
import ApplicationServices
import CoreGraphics
import ScreenCaptureKit

/// Discovers windows across all Spaces (including minimized / occluded / other
/// desktops) via the Accessibility API, captures thumbnails (ScreenCaptureKit),
/// and raises/focuses a target window.
enum WindowManager {

    // MARK: - Enumeration

    /// All switchable windows. On-screen windows come first in front-to-back
    /// z-order; minimized / off-Space windows follow.
    ///
    /// - Parameters:
    ///   - includeMinimized: keep minimized windows in the list.
    ///   - allSpaces: include windows that live on other Spaces / desktops.
    static func listWindows(
        excludingPID ownPID: pid_t,
        includeMinimized: Bool,
        allSpaces: Bool
    ) -> [WindowInfo] {
        // 1) Front-to-back z-order of the windows currently on screen (CG list).
        var zOrder: [CGWindowID: Int] = [:]
        if let raw = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] {
            for (index, entry) in raw.enumerated() {
                if let num = entry[kCGWindowNumber as String] as? CGWindowID, zOrder[num] == nil {
                    zOrder[num] = index
                }
            }
        }

        // 2) Every window of every regular app, via Accessibility.
        var result: [WindowInfo] = []
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ownPID && !$0.isTerminated
        }

        for app in apps {
            let pid = app.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)
            // Don't let an unresponsive app stall the switcher.
            AXUIElementSetMessagingTimeout(appElement, 0.25)

            var windowsValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
                  let axWindows = windowsValue as? [AXUIElement] else { continue }

            let appName = app.localizedName ?? ""
            let icon = app.icon

            for axWindow in axWindows {
                // Only real top-level windows (skip palettes, toolbars, sheets…).
                guard axString(axWindow, kAXRoleAttribute) == (kAXWindowRole as String) else { continue }
                if let subrole = axString(axWindow, kAXSubroleAttribute),
                   subrole != (kAXStandardWindowSubrole as String),
                   subrole != (kAXDialogSubrole as String) {
                    continue
                }

                var wid: CGWindowID = 0
                let hasWID = _AXUIElementGetWindow(axWindow, &wid) == .success && wid != 0
                let minimized = axBool(axWindow, kAXMinimizedAttribute) ?? false
                let title = axString(axWindow, kAXTitleAttribute) ?? ""
                let bounds = axFrame(axWindow) ?? .zero

                // Drop tiny helper windows, but never drop a minimized one on size.
                if !minimized && (bounds.width < 60 || bounds.height < 60) { continue }
                // Junk with neither a window id nor a title isn't switch-worthy.
                if !hasWID && title.isEmpty { continue }

                // Stable identity: real CGWindowID when available, else a synthetic
                // id kept out of the normal (small, increasing) CGWindowID range.
                let identity: CGWindowID = hasWID
                    ? wid
                    : (0xF000_0000 | (CGWindowID(truncatingIfNeeded: CFHash(axWindow)) & 0x0FFF_FFFF))

                // Apply user filters.
                if minimized && !includeMinimized { continue }
                let onCurrentSpace = zOrder[identity] != nil
                if !allSpaces && !onCurrentSpace && !minimized { continue }

                result.append(
                    WindowInfo(
                        id: identity,
                        pid: pid,
                        appName: appName,
                        title: title,
                        appIcon: icon,
                        bounds: bounds,
                        isMinimized: minimized,
                        axElement: axWindow
                    )
                )
            }
        }

        // 3) On-screen windows first (by z-order), everything else after.
        result.sort { (zOrder[$0.id] ?? Int.max) < (zOrder[$1.id] ?? Int.max) }
        return result
    }

    // MARK: - Accessibility helpers

    private static func axString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func axBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    private static func axFrame(_ element: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        if let posValue, CFGetTypeID(posValue) == AXValueGetTypeID() {
            AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
        }
        if let sizeValue, CFGetTypeID(sizeValue) == AXValueGetTypeID() {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        }
        return CGRect(origin: point, size: size)
    }

    // MARK: - Thumbnails (ScreenCaptureKit)

    /// Captures thumbnails for the given windows concurrently, delivering each
    /// image to `onImage` (on the main actor) as soon as it is ready. Only
    /// on-screen (capturable) windows produce an image; the rest keep their
    /// app-icon placeholder.
    static func captureThumbnails(
        for windows: [WindowInfo],
        maxDimension: CGFloat,
        onImage: @escaping @MainActor (CGWindowID, NSImage) -> Void
    ) async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        ) else { return }

        var scByID: [CGWindowID: SCWindow] = [:]
        for w in content.windows { scByID[w.windowID] = w }

        await withTaskGroup(of: (CGWindowID, NSImage?).self) { group in
            for window in windows {
                guard let scWindow = scByID[window.id] else { continue }
                group.addTask {
                    (window.id, await capture(scWindow, maxDimension: maxDimension))
                }
            }
            for await (id, image) in group {
                if let image { await onImage(id, image) }
            }
        }
    }

    private static func capture(_ scWindow: SCWindow, maxDimension: CGFloat) async -> NSImage? {
        let w = scWindow.frame.width
        let h = scWindow.frame.height
        guard w > 1, h > 1 else { return nil }

        let scale = min(1.0, maxDimension / max(w, h))
        let config = SCStreamConfiguration()
        config.width = max(1, Int((w * scale).rounded()))
        config.height = max(1, Int((h * scale).rounded()))
        config.showsCursor = false
        config.scalesToFit = true

        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        guard let cgImage = try? await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config
        ) else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    // MARK: - Focus

    /// Un-minimize (if needed), raise, and focus the given window, then activate
    /// its owning application. Uses the window's cached AX element directly.
    static func focus(_ window: WindowInfo) {
        if let axWindow = window.axElement {
            if window.isMinimized {
                AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(axWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
        NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
    }
}
