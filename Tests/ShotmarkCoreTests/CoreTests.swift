import AppKit
import Carbon.HIToolbox
import Testing
@testable import ShotmarkCore

private func close(_ a: CGPoint, _ b: CGPoint, _ eps: CGFloat = 0.001) -> Bool {
    abs(a.x - b.x) < eps && abs(a.y - b.y) < eps
}

@Suite struct SelectionGeometryTests {
    @Test func rectNormalizesAnyDragDirection() {
        let r = SelectionGeometry.rect(from: CGPoint(x: 50, y: 80), to: CGPoint(x: 10, y: 20))
        #expect(r == CGRect(x: 10, y: 20, width: 40, height: 60))
    }

    @Test func handleHitTesting() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        #expect(SelectionGeometry.handle(at: CGPoint(x: 102, y: 98), in: r) == .topLeft)
        #expect(SelectionGeometry.handle(at: CGPoint(x: 200, y: 200), in: r) == .bottom)
        #expect(SelectionGeometry.handle(at: CGPoint(x: 300, y: 150), in: r) == .right)
        #expect(SelectionGeometry.handle(at: CGPoint(x: 150, y: 150), in: r) == nil)
    }

    @Test func resizeMovesOnlyOwnedEdges() {
        let r = CGRect(x: 10, y: 10, width: 100, height: 100)
        #expect(SelectionGeometry.resize(r, handle: .right, by: CGVector(dx: 20, dy: 999)) == CGRect(x: 10, y: 10, width: 120, height: 100))
        #expect(SelectionGeometry.resize(r, handle: .topLeft, by: CGVector(dx: 5, dy: -5)) == CGRect(x: 15, y: 5, width: 95, height: 105))
    }

    @Test func resizePastOppositeEdgeFlips() {
        let r = CGRect(x: 10, y: 10, width: 100, height: 100)
        #expect(SelectionGeometry.resize(r, handle: .left, by: CGVector(dx: 150, dy: 0)) == CGRect(x: 110, y: 10, width: 50, height: 100))
    }

    @Test func clampKeepsSizeInsideBounds() {
        let b = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let r = SelectionGeometry.clamp(CGRect(x: 950, y: -30, width: 100, height: 100), to: b)
        #expect(r == CGRect(x: 900, y: 0, width: 100, height: 100))
    }

    @Test func constrainLineSnapsTo45Degrees() {
        let a = CGPoint.zero
        #expect(close(SelectionGeometry.constrainLine(from: a, to: CGPoint(x: 100, y: 5)), CGPoint(x: (100.0 * 100.0 + 25.0).squareRoot(), y: 0)))
        let diag = SelectionGeometry.constrainLine(from: a, to: CGPoint(x: 100, y: 90))
        #expect(abs(diag.x - diag.y) < 0.001)
    }

    @Test func constrainSquareKeepsDirection() {
        #expect(SelectionGeometry.constrainSquare(from: .zero, to: CGPoint(x: -30, y: 10)) == CGPoint(x: -30, y: 30))
    }

    @Test func arrowHeadIsSymmetricBehindTip() {
        let (l, r) = SelectionGeometry.arrowHead(from: .zero, to: CGPoint(x: 100, y: 0), length: 10)
        #expect(l.x < 100 && r.x < 100)
        #expect(abs(l.y + r.y) < 0.001)
    }
}

@Suite struct ToolbarLayoutTests {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let vSize = CGSize(width: 40, height: 300)
    let hSize = CGSize(width: 200, height: 40)

    @Test func verticalGoesRightThenLeftThenInside() {
        let mid = CGRect(x: 100, y: 100, width: 400, height: 400)
        #expect(ToolbarLayout.verticalOrigin(selection: mid, size: vSize, bounds: bounds) == CGPoint(x: 506, y: 200))
        let rightEdge = CGRect(x: 500, y: 100, width: 480, height: 400)
        #expect(ToolbarLayout.verticalOrigin(selection: rightEdge, size: vSize, bounds: bounds).x == 454)
        let full = bounds
        #expect(ToolbarLayout.verticalOrigin(selection: full, size: vSize, bounds: bounds).x == 954)
    }

    @Test func horizontalGoesBelowThenAboveThenInside() {
        let mid = CGRect(x: 100, y: 100, width: 400, height: 400)
        #expect(ToolbarLayout.horizontalOrigin(selection: mid, size: hSize, bounds: bounds) == CGPoint(x: 300, y: 506))
        let bottom = CGRect(x: 100, y: 300, width: 400, height: 490)
        #expect(ToolbarLayout.horizontalOrigin(selection: bottom, size: hSize, bounds: bounds).y == 254)
        #expect(ToolbarLayout.horizontalOrigin(selection: bounds, size: hSize, bounds: bounds).y == 754)
    }
}

@Suite struct AnnotationTests {
    @Test func shapeBuilderAppliesConstraints() {
        let s = Shape.make(tool: .rectangle, from: .zero, to: CGPoint(x: 50, y: 20), constrained: true)
        #expect(s == .rectangle(CGRect(x: 0, y: 0, width: 50, height: 50)))
        if case .line(_, let end) = Shape.make(tool: .line, from: .zero, to: CGPoint(x: 3, y: 100), constrained: true) {
            #expect(abs(end.x) < 0.001)
        } else {
            Issue.record("expected line")
        }
    }

    @Test func meaningfulness() {
        let red = NSColor.red
        #expect(!Annotation(shape: .rectangle(CGRect(x: 0, y: 0, width: 1, height: 50)), color: red, lineWidth: 3).isMeaningful)
        #expect(Annotation(shape: .freehand([.zero]), color: red, lineWidth: 3).isMeaningful)
        #expect(!Annotation(shape: .text("  ", .zero), color: red, lineWidth: 3).isMeaningful)
        #expect(Annotation(shape: .arrow(.zero, CGPoint(x: 10, y: 0)), color: red, lineWidth: 3).isMeaningful)
    }

    @Test func undoRedo() {
        var stack = AnnotationStack()
        let a = Annotation(shape: .line(.zero, CGPoint(x: 10, y: 10)), color: .red, lineWidth: 3)
        stack.add(a); stack.add(a)
        let undid = stack.undo()
        #expect(undid)
        #expect(stack.items.count == 1 && stack.canRedo)
        let redid = stack.redo()
        #expect(redid)
        #expect(stack.items.count == 2)
        stack.undo(); stack.add(a)
        #expect(!stack.canRedo)
        stack.undo(); stack.undo()
        let undidEmpty = stack.undo()
        #expect(!undidEmpty)
    }

    @Test func drawingIntoBitmapProducesInk() throws {
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 40, bitsPerSample: 8,
                                                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let ctx = try #require(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx.cgContext, flipped: true)
        Annotation(shape: .rectangle(CGRect(x: 5, y: 5, width: 30, height: 30)), color: .red, lineWidth: 4).draw()
        NSGraphicsContext.restoreGraphicsState()
        let px = try #require(rep.colorAt(x: 5, y: 20))
        #expect(px.redComponent > 0.9 && px.alphaComponent > 0.9)
        #expect(rep.colorAt(x: 20, y: 20)?.alphaComponent == 0)
    }
}

@Suite struct KeyComboTests {
    @Test func defaultIsF1() {
        #expect(KeyCombo.default.displayString == "F1")
        #expect(KeyCombo.default.isValidGlobal)
    }

    @Test func modifiersRoundTrip() {
        let m = KeyCombo.carbonModifiers(from: [.command, .option, .control, .shift])
        #expect(KeyCombo.symbols(for: m) == "⌃⌥⇧⌘")
    }

    @Test func plainLetterIsNotAValidGlobalShortcut() throws {
        let c = try #require(KeyCombo(keyCode: UInt16(kVK_ANSI_A), flags: [], characters: "a"))
        #expect(c.keyName == "A")
        #expect(!c.isValidGlobal)
        let f5 = try #require(KeyCombo(keyCode: UInt16(kVK_F5), flags: [], characters: nil))
        #expect(f5.keyName == "F5" && f5.isValidGlobal)
    }
}

@Suite struct PaletteTests {
    @Test func hexRoundTrip() throws {
        for (_, hex) in Palette.colors {
            #expect(try #require(NSColor(hex: hex)).hexString == hex)
        }
        #expect(NSColor(hex: "nope") == nil)
    }
}
