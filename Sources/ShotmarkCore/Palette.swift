import AppKit

public extension NSColor {
    /// "#RRGGBB" (sRGB). Returns nil for anything else.
    convenience init?(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255,
                  alpha: 1)
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        func byte(_ x: CGFloat) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
}

public enum Palette {
    public static let colors: [(name: String, hex: String)] = [
        ("Vermelho", "#FF3B30"),
        ("Laranja", "#FF9500"),
        ("Amarelo", "#FFCC00"),
        ("Verde", "#34C759"),
        ("Azul", "#007AFF"),
        ("Roxo", "#AF52DE"),
        ("Rosa", "#FF2D55"),
        ("Preto", "#000000"),
        ("Branco", "#FFFFFF"),
    ]

    public static let defaultHex = "#FF3B30"
    public static let lineWidthRange: ClosedRange<CGFloat> = 1...20
    public static let defaultLineWidth: CGFloat = 3
}
