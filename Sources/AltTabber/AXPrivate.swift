import ApplicationServices

/// Private (but stable, widely-used) CoreGraphics/AX bridge that returns the
/// `CGWindowID` backing an `AXUIElement` window. This is the reliable way to map
/// a window we discovered via `CGWindowListCopyWindowInfo` to the Accessibility
/// element we need in order to raise/focus it.
///
/// Same symbol relied upon by AltTab, Rectangle, yabai, etc.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement,
                           _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError
