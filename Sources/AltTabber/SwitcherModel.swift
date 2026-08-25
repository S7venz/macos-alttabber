import AppKit
import SwiftUI
import ApplicationServices

/// A single switchable window.
struct WindowInfo: Identifiable, Equatable {
    let id: CGWindowID          // CoreGraphics window number — stable identity
    let pid: pid_t
    let appName: String
    let title: String
    let appIcon: NSImage?
    let bounds: CGRect          // in screen (top-left origin) coordinates
    let isMinimized: Bool
    let axElement: AXUIElement? // the Accessibility element, for reliable focus

    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.id == rhs.id
    }

    /// Best label for the card: window title if it has one, else the app name.
    var displayTitle: String {
        title.isEmpty ? appName : title
    }

    func matches(_ query: String) -> Bool {
        title.localizedCaseInsensitiveContains(query) ||
        appName.localizedCaseInsensitiveContains(query)
    }
}

/// Observable state shared between the event-tap driven controller and the
/// SwiftUI overlay. Mutated only on the main actor.
@MainActor
final class SwitcherModel: ObservableObject {
    @Published var windows: [WindowInfo] = []       // full set
    @Published var filtered: [WindowInfo] = []       // set shown after search filter
    @Published var searchText: String = ""
    @Published var selectedIndex: Int = 0
    @Published var thumbnails: [CGWindowID: NSImage] = [:]
    @Published var visible: Bool = false

    /// Grid columns chosen for the current window set (used for layout + arrows).
    @Published var columns: Int = 1

    // Layout / behavior snapshot for the current presentation (from AppSettings).
    @Published var cardWidth: CGFloat = 222
    @Published var cardHeight: CGFloat = 170
    @Published var showTitles: Bool = true
    @Published var animationsEnabled: Bool = true

    /// Set by the controller — invoked when the user clicks / hovers a card.
    var onActivate: ((Int) -> Void)?
    var onHover: ((Int) -> Void)?

    var selectedWindow: WindowInfo? {
        guard filtered.indices.contains(selectedIndex) else { return nil }
        return filtered[selectedIndex]
    }

    func applyFilter() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        filtered = query.isEmpty ? windows : windows.filter { $0.matches(query) }
        if selectedIndex >= filtered.count {
            selectedIndex = max(0, filtered.count - 1)
        }
    }

    func step(_ delta: Int) {
        guard !filtered.isEmpty else { return }
        let count = filtered.count
        selectedIndex = ((selectedIndex + delta) % count + count) % count
    }
}
