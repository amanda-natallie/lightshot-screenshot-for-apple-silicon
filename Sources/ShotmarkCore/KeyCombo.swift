import AppKit
import Carbon.HIToolbox

/// A global shortcut in Carbon terms (what RegisterEventHotKey expects).
public struct KeyCombo: Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var keyName: String

    public init(keyCode: UInt32, modifiers: UInt32, keyName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyName = keyName
    }

    /// F1
    public static let `default` = KeyCombo(keyCode: UInt32(kVK_F1), modifiers: 0, keyName: "F1")

    /// `characters` should be the key's characters with no modifiers applied.
    public init?(keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String?) {
        let name = Self.keyName(for: keyCode, characters: characters)
        guard !name.isEmpty else { return nil }
        self.init(keyCode: UInt32(keyCode), modifiers: Self.carbonModifiers(from: flags), keyName: name)
    }

    /// Global shortcuts need ⌘, ⌃ or ⌥ — unless it's a function key.
    public var isValidGlobal: Bool {
        modifiers & UInt32(cmdKey | controlKey | optionKey) != 0 || Self.functionKeys.contains(Int(keyCode))
    }

    public var displayString: String { Self.symbols(for: modifiers) + keyName }

    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    public static func symbols(for m: UInt32) -> String {
        var s = ""
        if m & UInt32(controlKey) != 0 { s += "⌃" }
        if m & UInt32(optionKey) != 0 { s += "⌥" }
        if m & UInt32(shiftKey) != 0 { s += "⇧" }
        if m & UInt32(cmdKey) != 0 { s += "⌘" }
        return s
    }

    static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    static let specialNames: [Int: String] = {
        var names: [Int: String] = [
            kVK_Space: "Espaço", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        ]
        for (i, code) in [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                          kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20].enumerated() {
            names[code] = "F\(i + 1)"
        }
        return names
    }()

    static func keyName(for keyCode: UInt16, characters: String?) -> String {
        if let special = specialNames[Int(keyCode)] { return special }
        return (characters ?? "").trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)).uppercased()
    }
}
