import Foundation
import CoreGraphics
import ApplicationServices

// MARK: - Private SkyLight / Process Manager symbols

@_silgen_name("GetProcessForPID")
private func _GetProcessForPID(_ pid: pid_t,
                               _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

@_silgen_name("_SLPSSetFrontProcessWithOptions")
private func _SLPSSetFrontProcessWithOptions(_ psn: UnsafeMutablePointer<ProcessSerialNumber>,
                                             _ wid: CGWindowID,
                                             _ mode: UInt32) -> CGError

@_silgen_name("SLPSPostEventRecordTo")
private func _SLPSPostEventRecordTo(_ psn: UnsafeMutablePointer<ProcessSerialNumber>,
                                    _ bytes: UnsafePointer<UInt8>) -> CGError

@_silgen_name("SLSMainConnectionID")
private func SLSMainConnectionID() -> Int32
@_silgen_name("SLSCopySpacesForWindows")
private func SLSCopySpacesForWindows(_ cid: Int32, _ mask: Int32, _ windows: CFArray) -> Unmanaged<CFArray>?
@_silgen_name("SLSCopyManagedDisplayForSpace")
private func SLSCopyManagedDisplayForSpace(_ cid: Int32, _ space: UInt64) -> Unmanaged<CFString>?
@_silgen_name("SLSManagedDisplayGetCurrentSpace")
private func SLSManagedDisplayGetCurrentSpace(_ cid: Int32, _ display: CFString) -> UInt64
@_silgen_name("SLSManagedDisplaySetCurrentSpace")
private func SLSManagedDisplaySetCurrentSpace(_ cid: Int32, _ display: CFString, _ space: UInt64)

enum SkyLight {
    private static let userGenerated: UInt32 = 0x200
    static let cid = SLSMainConnectionID()

    // MARK: Spaces (per display — essential for multi-monitor)

    static func spaceOfWindow(_ wid: CGWindowID) -> UInt64? {
        let windows = [wid] as CFArray
        guard let ref = SLSCopySpacesForWindows(cid, 0x7, windows)?.takeRetainedValue(),
              let spaces = ref as? [NSNumber], let s = spaces.first?.uint64Value, s != 0 else { return nil }
        return s
    }

    static func displayOfSpace(_ space: UInt64) -> String? {
        SLSCopyManagedDisplayForSpace(cid, space)?.takeRetainedValue() as String?
    }

    static func currentSpace(ofDisplay display: String) -> UInt64 {
        SLSManagedDisplayGetCurrentSpace(cid, display as CFString)
    }

    /// Make `space` current on its display. Must run on the main thread.
    static func setCurrentSpace(_ space: UInt64, display: String) {
        SLSManagedDisplaySetCurrentSpace(cid, display as CFString, space)
    }

    // MARK: Raise / focus

    /// Front the window's process + the window, then make it key.
    static func raiseWindow(_ wid: CGWindowID, pid: pid_t) {
        var psn = ProcessSerialNumber()
        guard _GetProcessForPID(pid, &psn) == 0 else { return }
        _ = _SLPSSetFrontProcessWithOptions(&psn, wid, userGenerated)
        makeKeyWindow(&psn, wid)
    }

    /// Make `wid` key via a synthetic left-mouse-down delivered to the window by
    /// id, aimed far past its bottom-right corner so no real control is hit.
    private static func makeKeyWindow(_ psn: inout ProcessSerialNumber, _ wid: CGWindowID) {
        var bytes = [UInt8](repeating: 0, count: 0x100)   // 0x100: WindowServer over-reads the 0xf8 record
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        var wid32 = wid
        withUnsafeBytes(of: &wid32) { src in
            for i in 0..<MemoryLayout<CGWindowID>.size { bytes[0x3c + i] = src[i] }
        }
        var point = CGPoint(x: 300_000, y: 300_000)
        withUnsafeBytes(of: &point) { src in
            for i in 0..<MemoryLayout<CGPoint>.size { bytes[0x20 + i] = src[i] }
        }
        bytes[0x08] = 0x01
        _ = _SLPSPostEventRecordTo(&psn, &bytes)
    }
}
