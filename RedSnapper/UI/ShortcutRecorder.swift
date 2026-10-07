import SwiftUI
import AppKit
import Carbon.HIToolbox
import SnapCore

/// A button that records a keyboard shortcut when clicked.
/// Esc cancels, Delete clears, and a shortcut needs ⌃, ⌥ or ⌘ (except F-keys).
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?
    /// Called with `true` when recording starts and `false` when it ends, so global
    /// hotkeys can be suspended (otherwise they'd swallow the very keys being recorded).
    var onRecordingChange: (Bool) -> Void = { _ in }

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var resignObserver: Any?

    var body: some View {
        Button(action: toggle) {
            Text(label)
                .font(.system(.body, design: .rounded).monospacedDigit())
                .frame(minWidth: 110)
                .foregroundStyle(isRecording ? Color.red : (combo == nil ? .secondary : .primary))
        }
        .help(isRecording ? "Type a shortcut · Esc to cancel · Delete to clear" : "Click to record a new shortcut")
        .onDisappear(perform: stop)
    }

    private var label: String {
        if isRecording { return "Type shortcut…" }
        return combo?.displayString ?? "None"
    }

    private func toggle() { isRecording ? stop() : start() }

    private func start() {
        isRecording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil // swallow while recording
        }
        // Clicking away (or closing Settings) cancels, so hotkeys are never left suspended.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { _ in stop() }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        if isRecording {
            isRecording = false
            onRecordingChange(false)
        }
    }

    private func handle(_ event: NSEvent) {
        let keyCode = Int(event.keyCode)
        let modifiers = Self.carbonModifiers(from: event.modifierFlags)

        if keyCode == kVK_Escape && modifiers == 0 { return stop() }
        if (keyCode == kVK_Delete || keyCode == kVK_ForwardDelete) && modifiers == 0 {
            combo = nil
            return stop()
        }
        let hasCommandLikeModifier = modifiers & (KeyCombo.control | KeyCombo.option | KeyCombo.cmd) != 0
        let isFunctionKey = KeyCodes.name(for: UInt32(keyCode)).hasPrefix("F")
        guard hasCommandLikeModifier || isFunctionKey else { NSSound.beep(); return }

        combo = KeyCombo(keyCode: UInt32(keyCode), modifiers: modifiers)
        stop()
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.control) { m |= KeyCombo.control }
        if flags.contains(.option) { m |= KeyCombo.option }
        if flags.contains(.shift) { m |= KeyCombo.shift }
        if flags.contains(.command) { m |= KeyCombo.cmd }
        return m
    }
}
