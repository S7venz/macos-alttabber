import AppKit
import ApplicationServices
import CoreGraphics
import ScreenCaptureKit

/// Discovers windows across all Spaces, captures thumbnails (ScreenCaptureKit),
/// and raises/focuses a target window (Accessibility on the current Space,
/// SkyLight for windows on other Spaces).
enum WindowManager {

    // MARK: - Enumeration

    /// All switchable windows. On-screen windows come first (front-to-back
    /// z-order); minimized / off-Space windows follow.
    ///
    /// - Parameters:
    ///   - includeMinimized: keep minimized windows.
    ///   - allSpaces: include windows on other Spaces / desktops.
    static func listWindows(
        excludingPID ownPID: pid_t,
        includeMinimized: Bool,
        allSpaces: Bool
    ) -> [WindowInfo] {
        // 1) Front-to-back z-order of the windows on the current Space.
        var zOrder: [CGWindowID: Int] = [:]
        if let onscreen = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] {
            for (index, entry) in onscreen.enumerated() {
                if let num = entry[kCGWindowNumber as String] as? CGWindowID, zOrder[num] == nil {
                    zOrder[num] = index
                }
            }
        }

        // 2) Accessibility pass: minimized flags + element map (current Space only).
        var minimizedIDs = Set<CGWindowID>()
        var axByID: [CGWindowID: AXUIElement] = [:]
        for app in NSWorkspace.shared.runningApplications
            where app.activationPolicy == .regular && app.processIdentifier != ownPID && !app.isTerminated {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.25)
            var windowsValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
                  let axWindows = windowsValue as? [AXUIElement] else { continue }
            for axWindow in axWindows {
                var wid: CGWindowID = 0
                guard _AXUIElementGetWindow(axWindow, &wid) == .success, wid != 0 else { continue }
                axByID[wid] = axWindow
                if axBool(axWindow, kAXMinimizedAttribute) == true { minimizedIDs.insert(wid) }
            }
        }

        // 3) Full window list (all Spaces), filtered down to real, switchable windows.
        guard let all = CGWindowListCopyWindowInfo(
            [.excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        var iconCache: [pid_t: NSImage?] = [:]
        func icon(for pid: pid_t) -> NSImage? {
            if let cached = iconCache[pid] { return cached }
            let image = NSRunningApplication(processIdentifier: pid)?.icon
            iconCache[pid] = image
            return image
        }
        var regularCache: [pid_t: Bool] = [:]
        func isRegular(_ pid: pid_t) -> Bool {
            if let cached = regularCache[pid] { return cached }
            let regular = NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
            regularCache[pid] = regular
            return regular
        }

        var result: [WindowInfo] = []
        for entry in all {
            guard
                (entry[kCGWindowLayer as String] as? Int) == 0,
                let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                let num = entry[kCGWindowNumber as String] as? CGWindowID,
                isRegular(pid)
            else { continue }

            if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha < 0.05 { continue }

            var bounds = CGRect.zero
            if let b = entry[kCGWindowBounds as String] as? [String: Any],
               let rect = CGRect(dictionaryRepresentation: b as CFDictionary) {
                bounds = rect
            }
            if bounds.width < 60 || bounds.height < 60 { continue }

            let ownerName = entry[kCGWindowOwnerName as String] as? String ?? ""
            let title = entry[kCGWindowName as String] as? String ?? ""
            let visible = zOrder[num] != nil
            let minimized = minimizedIDs.contains(num)

            // Filters.
            if minimized && !includeMinimized { continue }
            if !allSpaces && !visible && !minimized { continue }
            // Off-screen windows with no title are almost always helper/placeholder
            // windows; keep only titled ones (visible windows may legitimately be untitled).
            if !visible && title.isEmpty { continue }

            result.append(
                WindowInfo(
                    id: num,
                    pid: pid,
                    appName: ownerName,
                    title: title,
                    appIcon: icon(for: pid),
                    bounds: bounds,
                    isMinimized: minimized,
                    axElement: axByID[num]
                )
            )
        }

        // On-screen windows first (z-order), everything else after (stable).
        result.sort { (zOrder[$0.id] ?? Int.max) < (zOrder[$1.id] ?? Int.max) }
        return result
    }

    // MARK: - Accessibility helpers

    private static func axBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    // MARK: - Thumbnails (ScreenCaptureKit)

    /// Captures thumbnails for the given windows concurrently, delivering each
    /// image to `onImage` (on the main actor) as soon as it is ready. Only
    /// capturable (on-screen) windows produce an image; the rest keep their
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

    /// Un-minimize (if needed) then raise + focus the window. Uses SkyLight so it
    /// works even when the window is on another Space.
    static func focus(_ window: WindowInfo) {
        if window.isMinimized, let axWindow = window.axElement {
            AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }

        if !SkyLight.raise(window.id, pid: window.pid) {
            // Fallback if the process couldn't be resolved.
            if let axWindow = window.axElement {
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
            }
            NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
        }
    }
}
