import AppKit
import Carbon.HIToolbox
import ShotmarkCore
import UniformTypeIdentifiers

/// The interactive layer over one frozen display: selection, annotation, toolbars, export.
/// Coordinates are flipped (top-left origin) view points.
@MainActor
final class OverlayView: NSView, NSTextFieldDelegate {
    private enum Drag {
        case none
        case selecting(start: CGPoint)
        case moving(start: CGPoint, original: CGRect)
        case resizing(Handle, start: CGPoint, original: CGRect)
        case drawing(start: CGPoint)
    }

    private let image: CGImage
    private let pixelScale: CGFloat
    private weak var controller: CaptureController?

    private var selection: CGRect?
    private var annotations = AnnotationStack()
    private var inProgress: Annotation?
    private var drag: Drag = .none
    private var tool: Tool? { didSet { refreshToolbarState() } }
    private var color = Settings.color { didSet { Settings.color = color; textField?.textColor = color; refreshToolbarState() } }
    private var lineWidth = Settings.lineWidth { didSet { Settings.lineWidth = lineWidth; refreshToolbarState() } }
    private var scrollAccumulator: CGFloat = 0

    private var textField: NSTextField?
    private var textOrigin: CGPoint = .zero

    private var toolButtons: [Tool: ToolbarButton] = [:]
    private var colorButton: ToolbarButton!
    private var undoButton: ToolbarButton!
    private var drawBar: Toolbar!
    private var actionBar: Toolbar!

    init(frame: NSRect, image: CGImage, controller: CaptureController) {
        self.image = image
        self.pixelScale = CGFloat(image.width) / max(frame.width, 1)
        self.controller = controller
        super.init(frame: frame)
        buildToolbars()
        layoutToolbars()
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Toolbars

    private func buildToolbars() {
        let tools: [(Tool, String, String)] = [
            (.pencil, "pencil", "Lápis (P)"),
            (.line, "line.diagonal", "Linha (L)"),
            (.arrow, "arrow.up.right", "Seta (A)"),
            (.rectangle, "rectangle", "Retângulo (R)"),
            (.ellipse, "circle", "Elipse (E)"),
            (.marker, "highlighter", "Marca-texto (M)"),
            (.text, "textformat", "Texto (T)"),
        ]
        var drawButtons: [ToolbarButton] = tools.map { tool, symbol, tip in
            let b = ToolbarButton(symbol: symbol, tooltip: tip) { [weak self] in self?.toggle(tool) }
            toolButtons[tool] = b
            return b
        }
        colorButton = ToolbarButton(symbol: "circle.fill", tooltip: "Cor · role para mudar a espessura") { [weak self] in self?.showColorMenu() }
        undoButton = ToolbarButton(symbol: "arrow.uturn.backward", tooltip: "Desfazer (⌘Z)") { [weak self] in self?.undo() }
        drawButtons += [colorButton, undoButton]
        drawBar = Toolbar(vertical: true, buttons: drawButtons)

        actionBar = Toolbar(vertical: false, buttons: [
            ToolbarButton(symbol: "doc.on.doc", tooltip: "Copiar (⌘C)") { [weak self] in self?.copyAndClose() },
            ToolbarButton(symbol: "square.and.arrow.down", tooltip: "Salvar (⌘S)") { [weak self] in self?.save() },
            ToolbarButton(symbol: "printer", tooltip: "Imprimir (⌘P)") { [weak self] in self?.printSelection() },
            ToolbarButton(symbol: "xmark", tooltip: "Fechar (Esc)") { [weak self] in self?.controller?.finish() },
        ])
        addSubview(drawBar)
        addSubview(actionBar)
        refreshToolbarState()
    }

    private func refreshToolbarState() {
        for (t, b) in toolButtons { b.isSelected = (t == tool) }
        colorButton?.swatch = (color, min(8 + lineWidth, 22))
        undoButton?.isEnabled = annotations.canUndo
    }

    private func layoutToolbars() {
        var isSelecting = false
        if case .selecting = drag { isSelecting = true }
        let show = selection != nil && !isSelecting
        drawBar.isHidden = !show
        actionBar.isHidden = !show
        guard show, let sel = selection else { return }
        drawBar.setFrameOrigin(ToolbarLayout.verticalOrigin(selection: sel, size: drawBar.frame.size, bounds: bounds))
        actionBar.setFrameOrigin(ToolbarLayout.horizontalOrigin(selection: sel, size: actionBar.frame.size, bounds: bounds))
    }

    private func toggle(_ t: Tool) {
        commitText()
        tool = (tool == t) ? nil : t
        window?.makeFirstResponder(self)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSColor(white: 0, alpha: 0.45)
        guard let sel = selection else {
            dim.setFill()
            bounds.fill()
            drawHint()
            return
        }
        let shade = NSBezierPath(rect: bounds)
        shade.append(NSBezierPath(rect: sel))
        shade.windingRule = .evenOdd
        dim.setFill()
        shade.fill()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: sel).addClip()
        annotations.items.forEach { $0.draw() }
        inProgress?.draw()
        NSGraphicsContext.restoreGraphicsState()

        drawSelectionChrome(sel)
    }

    private func drawSelectionChrome(_ sel: CGRect) {
        let border = NSBezierPath(rect: sel.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        NSColor.white.setStroke()
        border.stroke()
        border.setLineDash([4, 4], count: 2, phase: 0)
        NSColor.black.setStroke()
        border.stroke()

        for h in Handle.allCases {
            let c = SelectionGeometry.point(of: h, in: sel)
            let r = NSRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7)
            NSColor.white.setFill()
            r.fill()
            NSColor(white: 0, alpha: 0.6).setStroke()
            NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }

        let w = Int((sel.width * outputScale).rounded()), h = Int((sel.height * outputScale).rounded())
        drawBadge("\(w) × \(h)", above: sel)
    }

    private func drawBadge(_ text: String, above sel: CGRect) {
        let label = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ])
        let size = label.size()
        var r = NSRect(x: sel.minX, y: sel.minY - size.height - 10, width: size.width + 12, height: size.height + 4)
        if r.minY < bounds.minY { r.origin.y = sel.minY + 4; r.origin.x += 4 }
        r.origin.x = min(r.origin.x, bounds.maxX - r.width)
        NSColor(white: 0.1, alpha: 0.85).setFill()
        NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill()
        label.draw(at: NSPoint(x: r.minX + 6, y: r.minY + 2))
    }

    private func drawHint() {
        let hint = NSAttributedString(string: "Arraste para selecionar uma área  ·  Esc para sair", attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor(white: 1, alpha: 0.9),
        ])
        let s = hint.size()
        let r = NSRect(x: bounds.midX - s.width / 2 - 14, y: bounds.midY - s.height / 2 - 8, width: s.width + 28, height: s.height + 16)
        NSColor(white: 0.1, alpha: 0.75).setFill()
        NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
        hint.draw(at: NSPoint(x: r.minX + 14, y: r.minY + 8))
    }

    // MARK: - Mouse

    private func location(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with e: NSEvent) { updateCursor(at: location(e)) }

    override func mouseDown(with e: NSEvent) {
        commitText()
        window?.makeKey()
        window?.makeFirstResponder(self)
        let p = location(e)

        if let sel = selection {
            if e.clickCount == 2, sel.contains(p), tool == nil { copyAndClose(); return }
            if let h = SelectionGeometry.handle(at: p, in: sel) {
                drag = .resizing(h, start: p, original: sel)
                return
            }
            if sel.contains(p) {
                switch tool {
                case .text?:
                    beginText(at: p)
                case let t?:
                    drag = .drawing(start: p)
                    inProgress = Annotation(shape: t.isFreehand ? .freehand([p]) : Shape.make(tool: t, from: p, to: p, constrained: false),
                                            color: color, lineWidth: lineWidth, isMarker: t == .marker)
                    needsDisplay = true
                case nil:
                    drag = .moving(start: p, original: sel)
                    NSCursor.closedHand.set()
                }
                return
            }
            // Clicking outside never throws away annotations; Esc or undo first.
            if annotations.canUndo { return }
        }

        controller?.selectionBegan(in: self)
        selection = nil
        drag = .selecting(start: p)
        layoutToolbars()
        needsDisplay = true
    }

    override func mouseDragged(with e: NSEvent) {
        let raw = location(e)
        let p = SelectionGeometry.clamp(raw, to: bounds)
        switch drag {
        case .none:
            return
        case .selecting(let start):
            selection = SelectionGeometry.rect(from: start, to: p)
        case .moving(let start, let original):
            selection = SelectionGeometry.clamp(original.offsetBy(dx: raw.x - start.x, dy: raw.y - start.y), to: bounds)
        case .resizing(let h, let start, let original):
            selection = SelectionGeometry.resize(original, handle: h, by: CGVector(dx: p.x - start.x, dy: p.y - start.y)).intersection(bounds)
        case .drawing(let start):
            guard let t = tool, var a = inProgress else { return }
            let shift = e.modifierFlags.contains(.shift)
            if t.isFreehand, !shift, case .freehand(var pts) = a.shape {
                pts.append(p)
                a.shape = .freehand(pts)
            } else {
                a.shape = Shape.make(tool: t, from: start, to: p, constrained: shift)
            }
            inProgress = a
        }
        layoutToolbars()
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) {
        switch drag {
        case .selecting:
            if let sel = selection, sel.width < 3 || sel.height < 3 { selection = nil }
        case .drawing:
            if let a = inProgress, a.isMeaningful { annotations.add(a) }
            inProgress = nil
            refreshToolbarState()
        default:
            break
        }
        drag = .none
        layoutToolbars()
        updateCursor(at: location(e))
        needsDisplay = true
    }

    override func scrollWheel(with e: NSEvent) {
        scrollAccumulator += e.scrollingDeltaY
        let threshold: CGFloat = e.hasPreciseScrollingDeltas ? 10 : 1
        guard abs(scrollAccumulator) >= threshold else { return }
        let step: CGFloat = scrollAccumulator > 0 ? 1 : -1
        scrollAccumulator = 0
        lineWidth = min(max(lineWidth + step, Palette.lineWidthRange.lowerBound), Palette.lineWidthRange.upperBound)
        if let f = textField { f.font = Annotation.font(forLineWidth: lineWidth); fitTextField(f) }
    }

    private func updateCursor(at p: CGPoint) {
        if (!drawBar.isHidden && drawBar.frame.contains(p)) || (!actionBar.isHidden && actionBar.frame.contains(p)) {
            NSCursor.arrow.set()
            return
        }
        guard let sel = selection else { NSCursor.crosshair.set(); return }
        if let h = SelectionGeometry.handle(at: p, in: sel) {
            switch h {
            case .left, .right: NSCursor.resizeLeftRight.set()
            case .top, .bottom: NSCursor.resizeUpDown.set()
            default: NSCursor.crosshair.set()
            }
        } else if sel.contains(p) {
            switch tool {
            case nil: NSCursor.openHand.set()
            case .text?: NSCursor.iBeam.set()
            default: NSCursor.crosshair.set()
            }
        } else {
            NSCursor.crosshair.set()
        }
    }

    // MARK: - Keyboard

    override func keyDown(with e: NSEvent) {
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = e.charactersIgnoringModifiers?.lowercased() ?? ""

        switch Int(e.keyCode) {
        case kVK_Escape:
            controller?.finish(); return
        case kVK_Return, kVK_ANSI_KeypadEnter:
            copyAndClose(); return
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow:
            nudge(keyCode: Int(e.keyCode), by: flags.contains(.shift) ? 10 : 1); return
        default:
            break
        }

        if flags.contains(.command) {
            switch key {
            case "c": copyAndClose()
            case "s": save()
            case "p": printSelection()
            case "a": selectAll()
            case "z": flags.contains(.shift) ? redo() : undo()
            default: super.keyDown(with: e)
            }
            return
        }

        let shortcuts: [String: Tool] = ["p": .pencil, "l": .line, "a": .arrow, "r": .rectangle, "e": .ellipse, "m": .marker, "t": .text]
        if selection != nil, let t = shortcuts[key] { toggle(t) } else { super.keyDown(with: e) }
    }

    private func nudge(keyCode: Int, by d: CGFloat) {
        guard let sel = selection else { return }
        let delta: CGVector = switch keyCode {
        case kVK_LeftArrow: CGVector(dx: -d, dy: 0)
        case kVK_RightArrow: CGVector(dx: d, dy: 0)
        case kVK_UpArrow: CGVector(dx: 0, dy: -d)
        default: CGVector(dx: 0, dy: d)
        }
        selection = SelectionGeometry.clamp(sel.offsetBy(dx: delta.dx, dy: delta.dy), to: bounds)
        layoutToolbars()
        needsDisplay = true
    }

    private func selectAll() {
        controller?.selectionBegan(in: self)
        selection = bounds
        layoutToolbars()
        needsDisplay = true
    }

    private func undo() {
        commitText()
        annotations.undo()
        refreshToolbarState()
        needsDisplay = true
    }

    private func redo() {
        annotations.redo()
        refreshToolbarState()
        needsDisplay = true
    }

    /// Called when another display starts a selection.
    func reset() {
        commitText()
        selection = nil
        annotations = AnnotationStack()
        inProgress = nil
        drag = .none
        refreshToolbarState()
        layoutToolbars()
        needsDisplay = true
    }

    // MARK: - Text tool

    private func beginText(at p: CGPoint) {
        let f = NSTextField(string: "")
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = Annotation.font(forLineWidth: lineWidth)
        f.textColor = color
        f.delegate = self
        f.cell?.wraps = false
        f.cell?.isScrollable = true
        f.placeholderString = "Texto"
        textOrigin = p
        addSubview(f)
        fitTextField(f)
        window?.makeFirstResponder(f)
        textField = f
    }

    private func fitTextField(_ f: NSTextField) {
        f.sizeToFit()
        // NSTextField insets its text by ~2pt; offset so the committed text lands where it was typed.
        f.frame = NSRect(x: textOrigin.x - 2, y: textOrigin.y, width: max(f.frame.width + 12, 60), height: f.frame.height)
    }

    func controlTextDidChange(_ obj: Notification) {
        if let f = textField { fitTextField(f) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) { commitText(); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) { discardText(); return true }
        return false
    }

    private func commitText() {
        guard let f = textField else { return }
        let a = Annotation(shape: .text(f.stringValue, textOrigin), color: color, lineWidth: lineWidth)
        discardText()
        if a.isMeaningful { annotations.add(a) }
        refreshToolbarState()
        needsDisplay = true
    }

    private func discardText() {
        guard let f = textField else { return }
        textField = nil
        f.delegate = nil
        f.removeFromSuperview()
        window?.makeFirstResponder(self)
    }

    // MARK: - Color

    private func showColorMenu() {
        commitText()
        let menu = NSMenu()
        for (name, hex) in Palette.colors {
            guard let c = NSColor(hex: hex) else { continue }
            let item = NSMenuItem(title: name, action: #selector(pickColor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = c
            item.image = swatchImage(c)
            item.state = c.hexString == color.hexString ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let custom = NSMenuItem(title: "Outra cor…", action: #selector(openColorPanel), keyEquivalent: "")
        custom.target = self
        menu.addItem(custom)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: colorButton.bounds.maxY + 2), in: colorButton)
    }

    private func swatchImage(_ c: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { r in
            c.setFill()
            let p = NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1))
            p.fill()
            NSColor(white: 0.5, alpha: 1).setStroke()
            p.stroke()
            return true
        }
    }

    @objc private func pickColor(_ item: NSMenuItem) {
        if let c = item.representedObject as? NSColor { color = c }
    }

    @objc private func openColorPanel() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = color
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        panel.level = NSWindow.Level(rawValue: CaptureController.overlayLevel.rawValue + 1)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorPanelChanged(_ panel: NSColorPanel) {
        color = panel.color.usingColorSpace(.sRGB) ?? panel.color
    }

    // MARK: - Export

    private var outputScale: CGFloat { Settings.saveRetina ? pixelScale : 1 }

    /// Renders the selection (screenshot + annotations) at output resolution in the capture's color space.
    private func renderSelection() -> NSBitmapImageRep? {
        commitText()
        guard let sel = selection?.integral.intersection(bounds), sel.width >= 1, sel.height >= 1 else { return nil }
        let scale = outputScale
        let w = Int((sel.width * scale).rounded()), h = Int((sel.height * scale).rounded())
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high

        // Screenshot: CG is y-up, so the selection's bottom edge maps to y = 0.
        ctx.draw(image, in: CGRect(x: -sel.minX * scale, y: -(bounds.height - sel.maxY) * scale,
                                   width: bounds.width * scale, height: bounds.height * scale))

        // Annotations: switch to flipped view coordinates.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -sel.minX, y: -sel.minY)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        annotations.items.forEach { $0.draw() }
        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()

        guard let cg = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = sel.size
        return rep
    }

    private func copyAndClose() {
        guard let rep = renderSelection(), let png = rep.representation(using: .png, properties: [:]) else { NSSound.beep(); return }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = rep.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
        controller?.finish()
    }

    private func save() {
        guard let rep = renderSelection(), let png = rep.representation(using: .png, properties: [:]) else { NSSound.beep(); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.directoryURL = Settings.saveDirectory
        panel.nameFieldStringValue = Self.defaultFileName()

        controller?.setOverlaysLowered(true)
        let response = panel.runModal()
        controller?.setOverlaysLowered(false)

        guard response == .OK, let url = panel.url else {
            window?.makeKeyAndOrderFront(nil)
            window?.makeFirstResponder(self)
            return
        }
        do {
            try png.write(to: url, options: .atomic)
            Settings.saveDirectory = url.deletingLastPathComponent()
            controller?.finish()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func printSelection() {
        guard let rep = renderSelection() else { NSSound.beep(); return }
        controller?.finish()
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        let view = NSImageView(frame: NSRect(origin: .zero, size: rep.size))
        view.image = img
        view.imageScaling = .scaleProportionallyDown
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        NSApp.activate()
        NSPrintOperation(view: view, printInfo: info).run()
    }

    private static func defaultFileName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'às' HH.mm.ss"
        return "Captura \(f.string(from: Date())).png"
    }
}
