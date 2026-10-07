import Foundation
import Carbon.HIToolbox

/// A keyboard shortcut: a virtual key code plus Carbon modifier flags.
public struct KeyCombo: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public static let cmd = UInt32(cmdKey)
    public static let shift = UInt32(shiftKey)
    public static let option = UInt32(optionKey)
    public static let control = UInt32(controlKey)

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var displayString: String {
        var s = ""
        if modifiers & Self.control != 0 { s += "⌃" }
        if modifiers & Self.option != 0 { s += "⌥" }
        if modifiers & Self.shift != 0 { s += "⇧" }
        if modifiers & Self.cmd != 0 { s += "⌘" }
        return s + KeyCodes.name(for: keyCode)
    }
}

/// Every action that can be bound to a global hotkey.
public enum HotKeyAction: String, CaseIterable, Codable, Sendable, Identifiable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird
    case leftTwoThirds, rightTwoThirds
    case maximize, center
    case restore
    case nextDisplay, previousDisplay
    case fourUpGrid

    public var id: String { rawValue }

    /// The snap zone this action applies, for plain snapping actions.
    public var zone: SnapZone? { SnapZone(rawValue: rawValue) }

    public var displayName: String {
        switch self {
        case .fourUpGrid: return "4-Up Grid"
        case .restore: return "Restore Previous Size"
        default: return SnapZone.words(rawValue)
        }
    }

    /// How actions are grouped in the menu bar and in Settings → Shortcuts.
    public static let groups: [(title: String, actions: [HotKeyAction])] = [
        ("Halves", [.leftHalf, .rightHalf, .topHalf, .bottomHalf]),
        ("Quarters", [.topLeft, .topRight, .bottomLeft, .bottomRight]),
        ("Thirds", [.leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds]),
        ("Other", [.maximize, .center, .restore, .fourUpGrid]),
        ("Displays", [.nextDisplay, .previousDisplay]),
    ]

    /// Default bindings: Ctrl+Option + arrows / U I J K / D F G / Return / C / Delete,
    /// Ctrl+Option+Cmd + arrows for displays, Ctrl+Option+Q for the 4-up grid.
    /// Two-thirds have no default (they're reachable by pressing a half/third again).
    public static var defaultBindings: [HotKeyAction: KeyCombo] {
        let co = KeyCombo.control | KeyCombo.option
        let coc = co | KeyCombo.cmd
        return [
            .leftHalf: KeyCombo(keyCode: UInt32(kVK_LeftArrow), modifiers: co),
            .rightHalf: KeyCombo(keyCode: UInt32(kVK_RightArrow), modifiers: co),
            .topHalf: KeyCombo(keyCode: UInt32(kVK_UpArrow), modifiers: co),
            .bottomHalf: KeyCombo(keyCode: UInt32(kVK_DownArrow), modifiers: co),
            .topLeft: KeyCombo(keyCode: UInt32(kVK_ANSI_U), modifiers: co),
            .topRight: KeyCombo(keyCode: UInt32(kVK_ANSI_I), modifiers: co),
            .bottomLeft: KeyCombo(keyCode: UInt32(kVK_ANSI_J), modifiers: co),
            .bottomRight: KeyCombo(keyCode: UInt32(kVK_ANSI_K), modifiers: co),
            .leftThird: KeyCombo(keyCode: UInt32(kVK_ANSI_D), modifiers: co),
            .centerThird: KeyCombo(keyCode: UInt32(kVK_ANSI_F), modifiers: co),
            .rightThird: KeyCombo(keyCode: UInt32(kVK_ANSI_G), modifiers: co),
            .maximize: KeyCombo(keyCode: UInt32(kVK_Return), modifiers: co),
            .center: KeyCombo(keyCode: UInt32(kVK_ANSI_C), modifiers: co),
            .restore: KeyCombo(keyCode: UInt32(kVK_Delete), modifiers: co),
            .nextDisplay: KeyCombo(keyCode: UInt32(kVK_RightArrow), modifiers: coc),
            .previousDisplay: KeyCombo(keyCode: UInt32(kVK_LeftArrow), modifiers: coc),
            .fourUpGrid: KeyCombo(keyCode: UInt32(kVK_ANSI_Q), modifiers: co),
        ]
    }
}

/// Human-readable names for virtual key codes (the `kVK_*` constants in HIToolbox/Events.h).
public enum KeyCodes {
    private static let names: [UInt32: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X",
        0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y",
        0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=",
        0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]", 0x1F: "O", 0x20: "U",
        0x21: "[", 0x22: "I", 0x23: "P", 0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";",
        0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".", 0x32: "`",
        0x24: "↩", 0x30: "⇥", 0x31: "Space", 0x33: "⌫", 0x35: "⎋", 0x75: "⌦",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
        0x73: "↖", 0x77: "↘", 0x74: "⇞", 0x79: "⇟",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6",
        0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
        0x52: "Num0", 0x53: "Num1", 0x54: "Num2", 0x55: "Num3", 0x56: "Num4",
        0x57: "Num5", 0x58: "Num6", 0x59: "Num7", 0x5B: "Num8", 0x5C: "Num9",
    ]

    public static func name(for keyCode: UInt32) -> String {
        names[keyCode] ?? "Key\(keyCode)"
    }
}
