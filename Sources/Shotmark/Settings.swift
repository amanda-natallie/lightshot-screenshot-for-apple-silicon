import AppKit
import ShotmarkCore

/// Display name from the bundle, so the same binary can be packaged under another name (APP_NAME in build-app.sh).
enum AppInfo {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Shotmark"
}

/// UserDefaults-backed preferences.
enum Settings {
    private static let d = UserDefaults.standard

    static var hotKey: KeyCombo {
        get {
            guard d.object(forKey: "hotKeyCode") != nil, let name = d.string(forKey: "hotKeyName") else { return .default }
            return KeyCombo(keyCode: UInt32(d.integer(forKey: "hotKeyCode")),
                            modifiers: UInt32(d.integer(forKey: "hotKeyModifiers")),
                            keyName: name)
        }
        set {
            d.set(Int(newValue.keyCode), forKey: "hotKeyCode")
            d.set(Int(newValue.modifiers), forKey: "hotKeyModifiers")
            d.set(newValue.keyName, forKey: "hotKeyName")
        }
    }

    /// true: export at the display's native pixel density; false: 1 pixel per point.
    static var saveRetina: Bool {
        get { d.object(forKey: "saveRetina") as? Bool ?? true }
        set { d.set(newValue, forKey: "saveRetina") }
    }

    static var saveDirectory: URL {
        get { d.url(forKey: "saveDirectory") ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0] }
        set { d.set(newValue, forKey: "saveDirectory") }
    }

    static var color: NSColor {
        get { d.string(forKey: "color").flatMap { NSColor(hex: $0) } ?? NSColor(hex: Palette.defaultHex)! }
        set { d.set(newValue.hexString, forKey: "color") }
    }

    static var lineWidth: CGFloat {
        get {
            let v = d.double(forKey: "lineWidth")
            return v > 0 ? min(max(CGFloat(v), Palette.lineWidthRange.lowerBound), Palette.lineWidthRange.upperBound) : Palette.defaultLineWidth
        }
        set { d.set(Double(newValue), forKey: "lineWidth") }
    }
}
