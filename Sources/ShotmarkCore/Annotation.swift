import AppKit

public enum Tool: String, CaseIterable, Sendable {
    case pencil, line, arrow, rectangle, ellipse, marker, text

    public var isFreehand: Bool { self == .pencil || self == .marker }
}

public enum Shape: Equatable {
    case freehand([CGPoint])
    case line(CGPoint, CGPoint)
    case arrow(CGPoint, CGPoint)
    case rectangle(CGRect)
    case ellipse(CGRect)
    case text(String, CGPoint)

    /// Shape for a drag-defined tool. Freehand tools get a straight two-point stroke (used when Shift is held).
    public static func make(tool: Tool, from s: CGPoint, to p: CGPoint, constrained: Bool) -> Shape {
        switch tool {
        case .pencil, .marker:
            return .freehand([s, constrained ? SelectionGeometry.constrainLine(from: s, to: p) : p])
        case .line:
            return .line(s, constrained ? SelectionGeometry.constrainLine(from: s, to: p) : p)
        case .arrow:
            return .arrow(s, constrained ? SelectionGeometry.constrainLine(from: s, to: p) : p)
        case .rectangle:
            return .rectangle(SelectionGeometry.rect(from: s, to: constrained ? SelectionGeometry.constrainSquare(from: s, to: p) : p))
        case .ellipse:
            return .ellipse(SelectionGeometry.rect(from: s, to: constrained ? SelectionGeometry.constrainSquare(from: s, to: p) : p))
        case .text:
            return .text("", s)
        }
    }
}

public struct Annotation {
    public var shape: Shape
    public var color: NSColor
    public var lineWidth: CGFloat
    public var isMarker: Bool

    public init(shape: Shape, color: NSColor, lineWidth: CGFloat, isMarker: Bool = false) {
        self.shape = shape
        self.color = color
        self.lineWidth = lineWidth
        self.isMarker = isMarker
    }

    public static func font(forLineWidth w: CGFloat) -> NSFont {
        .systemFont(ofSize: 12 + w * 3, weight: .semibold)
    }

    public static let markerWidthFactor: CGFloat = 5
    public static let markerAlpha: CGFloat = 0.4

    /// False for accidental clicks that would leave an invisible or degenerate shape.
    public var isMeaningful: Bool {
        switch shape {
        case .freehand(let pts): !pts.isEmpty
        case .line(let a, let b), .arrow(let a, let b): hypot(b.x - a.x, b.y - a.y) >= 2
        case .rectangle(let r), .ellipse(let r): r.width >= 2 && r.height >= 2
        case .text(let s, _): !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Draws into the current NSGraphicsContext, which must be flipped (top-left origin).
    public func draw() {
        let ink = isMarker ? color.withAlphaComponent(Self.markerAlpha) : color
        ink.setStroke()
        ink.setFill()

        switch shape {
        case .freehand(let pts):
            guard let first = pts.first else { return }
            let path = NSBezierPath()
            path.move(to: first)
            if pts.count == 1 {
                path.line(to: first)
            } else {
                // Quadratic smoothing through segment midpoints.
                for i in 1..<pts.count {
                    let prev = pts[i - 1], cur = pts[i]
                    path.curve(to: CGPoint(x: (prev.x + cur.x) / 2, y: (prev.y + cur.y) / 2), controlPoint: prev)
                }
                path.line(to: pts[pts.count - 1])
            }
            path.lineWidth = isMarker ? lineWidth * Self.markerWidthFactor : lineWidth
            path.lineCapStyle = isMarker ? .square : .round
            path.lineJoinStyle = .round
            path.stroke()

        case .line(let a, let b):
            stroke(segmentFrom: a, to: b)

        case .arrow(let a, let b):
            let headLength = max(12, lineWidth * 4)
            let (l, r) = SelectionGeometry.arrowHead(from: a, to: b, length: headLength)
            if hypot(b.x - a.x, b.y - a.y) > headLength {
                stroke(segmentFrom: a, to: CGPoint(x: (l.x + r.x) / 2, y: (l.y + r.y) / 2))
            }
            let head = NSBezierPath()
            head.move(to: b)
            head.line(to: l)
            head.line(to: r)
            head.close()
            head.fill()

        case .rectangle(let rect):
            let path = NSBezierPath(rect: rect)
            path.lineWidth = lineWidth
            path.lineJoinStyle = .miter
            path.stroke()

        case .ellipse(let rect):
            let path = NSBezierPath(ovalIn: rect)
            path.lineWidth = lineWidth
            path.stroke()

        case .text(let string, let origin):
            NSAttributedString(string: string, attributes: [
                .font: Self.font(forLineWidth: lineWidth),
                .foregroundColor: color,
            ]).draw(at: origin)
        }
    }

    private func stroke(segmentFrom a: CGPoint, to b: CGPoint) {
        let path = NSBezierPath()
        path.move(to: a)
        path.line(to: b)
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.stroke()
    }
}

/// Annotation list with linear undo/redo.
public struct AnnotationStack {
    public private(set) var items: [Annotation] = []
    private var redoItems: [Annotation] = []

    public init() {}

    public var canUndo: Bool { !items.isEmpty }
    public var canRedo: Bool { !redoItems.isEmpty }

    public mutating func add(_ a: Annotation) {
        items.append(a)
        redoItems.removeAll()
    }

    @discardableResult
    public mutating func undo() -> Bool {
        guard let last = items.popLast() else { return false }
        redoItems.append(last)
        return true
    }

    @discardableResult
    public mutating func redo() -> Bool {
        guard let last = redoItems.popLast() else { return false }
        items.append(last)
        return true
    }
}
