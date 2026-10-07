#if os(macOS)
import AppKit
import ApplicationServices
import LauncherCore

struct TargetWindow {
    let id: CGWindowID
    let bounds: CGRect
}

@MainActor
final class TargetClient {
    let configuration: Configuration
    var application: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: configuration.bundleIdentifier)
            .first { !$0.isTerminated }
    }
    private var axWindow: AXUIElement?
    var log: (String) -> Void = { _ in }

    init(configuration: Configuration) { self.configuration = configuration }

    func applicationURL() -> URL? {
        let configured = URL(fileURLWithPath: configuration.applicationPath)
        if Bundle(url: configured)?.bundleIdentifier == configuration.bundleIdentifier { return configured }
        guard let discovered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: configuration.bundleIdentifier),
              Bundle(url: discovered)?.bundleIdentifier == configuration.bundleIdentifier else { return nil }
        return discovered
    }

    func launchOrAttach() {
        if let app = application {
            app.unhide()
            restoreMainWindow()
            log("attached-existing-client")
            return
        }
        guard let url = applicationURL() else {
            log("client-not-found: configure bundleIdentifier and applicationPath")
            return
        }
        let options = NSWorkspace.OpenConfiguration()
        options.activates = false
        options.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: url, configuration: options) { _, error in
            if let error = error {
                DispatchQueue.main.async { self.log("client-launch-failed: \(error.localizedDescription)") }
            }
        }
        log("client-launch-requested")
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }

    private func windows() -> [AXUIElement] {
        guard AXIsProcessTrusted(), let app = application else { return [] }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        // Limit a hung accessibility server so Esc and deadlines remain responsive.
        AXUIElementSetMessagingTimeout(element, 0.15)
        return attribute(element, kAXWindowsAttribute) as? [AXUIElement] ?? []
    }

    private func restoreMainWindow() {
        let list = windows()
        guard let main = list.first(where: { (attribute($0, kAXMainAttribute) as? Bool) == true }) ?? list.first else { return }
        AXUIElementSetMessagingTimeout(main, 0.15)
        AXUIElementSetAttributeValue(main, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
    }

    private func bounds(of window: AXUIElement) -> CGRect? {
        guard let position = attribute(window, kAXPositionAttribute),
              let size = attribute(window, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    func probe() -> TargetWindow? {
        guard let app = application,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { axWindow = nil; return nil }
        let candidates: [TargetWindow] = list.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
                  let id = info[kCGWindowNumber as String] as? NSNumber,
                  let dictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                  rect.width >= 320, rect.height >= 180 else { return nil }
            return TargetWindow(id: id.uint32Value, bounds: rect)
        }
        guard !candidates.isEmpty else { axWindow = nil; return nil }
        let accessible = windows()
        let main = accessible.first { (attribute($0, kAXMainAttribute) as? Bool) == true }
        let target: TargetWindow
        if let main = main, let rect = bounds(of: main) {
            target = candidates.min { distance($0.bounds, rect) < distance($1.bounds, rect) }!
        } else {
            // Front-to-back CG enumeration; prefer a substantial main window over a dialog.
            target = candidates.max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }!
        }
        axWindow = accessible.min { distance(bounds(of: $0) ?? .zero, target.bounds) < distance(bounds(of: $1) ?? .zero, target.bounds) }
        if let axWindow = axWindow, let rect = bounds(of: axWindow), distance(rect, target.bounds) > 80 {
            self.axWindow = nil
        }
        return target
    }

    private func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        abs(a.minX - b.minX) + abs(a.minY - b.minY) + abs(a.width - b.width) + abs(a.height - b.height)
    }

    @discardableResult
    func align(to frame: CGRect) -> Bool {
        guard configuration.matchClientToPlayer, AXIsProcessTrusted(), let window = axWindow else {
            log("alignment-unavailable: Accessibility permission or matching window missing")
            return false
        }
        let primaryHeight = Double(CGDisplayBounds(CGMainDisplayID()).height)
        let rect = Geometry.accessibilityRect(appKit: Rectangle(x: Double(frame.minX), y: Double(frame.minY),
                                                               width: Double(frame.width), height: Double(frame.height)),
                                              primaryDisplayHeight: primaryHeight)
        var point = CGPoint(x: rect.x, y: rect.y), size = CGSize(width: rect.width, height: rect.height)
        guard let position = AXValueCreate(.cgPoint, &point), let dimensions = AXValueCreate(.cgSize, &size) else { return false }
        // Public AX attributes only. Some clients enforce their own minimum size.
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        let resized = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
        let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        let expected = CGRect(origin: point, size: size)
        let exact = resized == .success && moved == .success && bounds(of: window).map { distance($0, expected) < 24 } == true
        log(exact ? "real-window-aligned" : "alignment-inexact: client constraints or AX denial")
        return exact
    }

    func handOff() {
        guard let app = application else { log("closed-without-client"); return }
        app.unhide()
        if let window = axWindow, AXIsProcessTrusted() {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
        app.activate(options: [.activateIgnoringOtherApps])
        log("focus-requested-for-real-client")
    }
}
#endif
