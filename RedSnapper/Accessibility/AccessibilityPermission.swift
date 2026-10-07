import AppKit
import ApplicationServices

/// Checks and requests the Accessibility (AX) trust that every window operation needs.
enum AccessibilityPermission {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system "would like to control this computer" prompt, which also
    /// adds RED SNAPPER to the list in System Settings so the user only has to flip the switch.
    @discardableResult
    static func requestWithSystemPrompt() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
