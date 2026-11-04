import AppKit

/// Icon button drawn by hand (NSButton styling doesn't fit a dark floating bar over arbitrary content).
final class ToolbarButton: NSView {
    static let side: CGFloat = 32

    var isSelected = false { didSet { needsDisplay = true } }
    var isEnabled = true { didSet { needsDisplay = true } }
    /// When set, the button draws a color swatch instead of its symbol.
    var swatch: (color: NSColor, diameter: CGFloat)? { didSet { needsDisplay = true } }

    private let icon: NSImage?
    private let dimIcon: NSImage?
    private let action: () -> Void
    private var hovering = false { didSet { needsDisplay = true } }

    init(symbol: String, tooltip: String, action: @escaping () -> Void) {
        let base = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        let size = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        icon = base?.withSymbolConfiguration(size.applying(.init(paletteColors: [.white])))
        dimIcon = base?.withSymbolConfiguration(size.applying(.init(paletteColors: [NSColor(white: 1, alpha: 0.3)])))
        self.action = action
        super.init(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.side))
        toolTip = tooltip
        setAccessibilityRole(.button)
        setAccessibilityLabel(tooltip)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; NSCursor.arrow.set() }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        action()
    }

    override func draw(_ dirtyRect: NSRect) {
        let bg = bounds.insetBy(dx: 2, dy: 2)
        if isSelected {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: bg, xRadius: 6, yRadius: 6).fill()
        } else if hovering && isEnabled {
            NSColor(white: 1, alpha: 0.14).setFill()
            NSBezierPath(roundedRect: bg, xRadius: 6, yRadius: 6).fill()
        }

        if let swatch {
            let d = swatch.diameter
            let r = NSRect(x: bounds.midX - d / 2, y: bounds.midY - d / 2, width: d, height: d)
            swatch.color.setFill()
            let circle = NSBezierPath(ovalIn: r)
            circle.fill()
            NSColor.white.setStroke()
            circle.lineWidth = 1.5
            circle.stroke()
            return
        }

        guard let image = isEnabled ? icon : dimIcon else { return }
        let s = image.size
        image.draw(in: NSRect(x: bounds.midX - s.width / 2, y: bounds.midY - s.height / 2, width: s.width, height: s.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

/// Rounded dark bar laying its buttons out in a row or column.
final class Toolbar: NSView {
    private static let padding: CGFloat = 4

    init(vertical: Bool, buttons: [ToolbarButton]) {
        let n = CGFloat(buttons.count), s = ToolbarButton.side, p = Self.padding
        let size = vertical ? NSSize(width: s + p * 2, height: s * n + p * 2) : NSSize(width: s * n + p * 2, height: s + p * 2)
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.11, alpha: 0.94).cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
        for (i, b) in buttons.enumerated() {
            b.setFrameOrigin(vertical ? NSPoint(x: p, y: p + CGFloat(i) * s) : NSPoint(x: p + CGFloat(i) * s, y: p))
            addSubview(b)
        }
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override var isFlipped: Bool { true }
    override func mouseDown(with event: NSEvent) {} // don't let clicks between buttons reach the overlay
}
