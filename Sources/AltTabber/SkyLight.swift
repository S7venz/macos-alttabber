import Foundation
import CoreGraphics
import ApplicationServices

// MARK: - Private SkyLight / Process Manager symbols
//
// These undocumented symbols are the only reliable way to raise and focus a
// window that lives on another Space, which the public Accessibility API cannot
// reach. Same approach used by AltTab, yabai, etc.

/// Deprecated in the public SDK but the symbol is still present; declared
/// directly to bypass the Swift availability annotation.
@_silgen_name("GetProcessForPID")
private func _GetProcessForPID(_ pid: pid_t,
                               _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

@_silgen_name("_SLPSSetFrontProcessWithOptions")
private func _SLPSSetFrontProcessWithOptions(_ psn: UnsafePointer<ProcessSerialNumber>,
                                             _ wid: CGWindowID,
                                             _ mode: UInt32) -> CGError

@_silgen_name("SLPSPostEventRecordTo")
private func _SLPSPostEventRecordTo(_ psn: UnsafePointer<ProcessSerialNumber>,
                                    _ bytes: UnsafePointer<UInt8>) -> CGError

enum SkyLight {
    private static let userGenerated: UInt32 = 0x200

    /// Bring `pid` to the front and make window `wid` key — works across Spaces
    /// (macOS switches to the window's Space automatically).
    /// Returns false if we couldn't resolve the process.
    @discardableResult
    static func raise(_ wid: CGWindowID, pid: pid_t) -> Bool {
        var psn = ProcessSerialNumber()
        guard _GetProcessForPID(pid, &psn) == 0 else { return false }

        _ = _SLPSSetFrontProcessWithOptions(&psn, wid, userGenerated)
        makeKeyWindow(&psn, wid)
        return true
    }

    /// Crafted SkyLight events that tell the app to treat `wid` as its key
    /// window (byte layout is the well-known AltTab recipe).
    private static func makeKeyWindow(_ psn: inout ProcessSerialNumber, _ wid: CGWindowID) {
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        var wid32 = wid
        withUnsafeBytes(of: &wid32) { src in
            for i in 0..<4 { bytes[0x3c + i] = src[i] }
        }
        for i in 0..<0x10 { bytes[0x20 + i] = 0xff }

        bytes[0x08] = 0x01
        _ = _SLPSPostEventRecordTo(&psn, &bytes)
        bytes[0x08] = 0x02
        _ = _SLPSPostEventRecordTo(&psn, &bytes)
    }
}
