import CoreGraphics

/// Resize handles around a selection. Coordinates are top-left origin (flipped view space).
public enum Handle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
}

public enum SelectionGeometry {
    /// Normalized rect spanning two points.
    public static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    public static func point(of handle: Handle, in r: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: CGPoint(x: r.minX, y: r.minY)
        case .top: CGPoint(x: r.midX, y: r.minY)
        case .topRight: CGPoint(x: r.maxX, y: r.minY)
        case .right: CGPoint(x: r.maxX, y: r.midY)
        case .bottomRight: CGPoint(x: r.maxX, y: r.maxY)
        case .bottom: CGPoint(x: r.midX, y: r.maxY)
        case .bottomLeft: CGPoint(x: r.minX, y: r.maxY)
        case .left: CGPoint(x: r.minX, y: r.midY)
        }
    }

    public static func handle(at p: CGPoint, in r: CGRect, tolerance: CGFloat = 6) -> Handle? {
        Handle.allCases.first { h in
            let c = point(of: h, in: r)
            return abs(c.x - p.x) <= tolerance && abs(c.y - p.y) <= tolerance
        }
    }

    /// Moves the edges owned by `handle` by `delta`; the result is re-normalized so dragging past the opposite edge flips.
    public static func resize(_ r: CGRect, handle: Handle, by d: CGVector) -> CGRect {
        var minX = r.minX, minY = r.minY, maxX = r.maxX, maxY = r.maxY
        switch handle {
        case .topLeft: minX += d.dx; minY += d.dy
        case .top: minY += d.dy
        case .topRight: maxX += d.dx; minY += d.dy
        case .right: maxX += d.dx
        case .bottomRight: maxX += d.dx; maxY += d.dy
        case .bottom: maxY += d.dy
        case .bottomLeft: minX += d.dx; maxY += d.dy
        case .left: minX += d.dx
        }
        return rect(from: CGPoint(x: minX, y: minY), to: CGPoint(x: maxX, y: maxY))
    }

    /// Shifts `r` (keeping its size) so it lies inside `bounds`.
    public static func clamp(_ r: CGRect, to bounds: CGRect) -> CGRect {
        var o = r.origin
        o.x = min(max(o.x, bounds.minX), bounds.maxX - r.width)
        o.y = min(max(o.y, bounds.minY), bounds.maxY - r.height)
        return CGRect(origin: o, size: r.size)
    }

    public static func clamp(_ p: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, bounds.minX), bounds.maxX), y: min(max(p.y, bounds.minY), bounds.maxY))
    }

    /// Snaps the segment a→b to the nearest multiple of 45°.
    public static func constrainLine(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let step = CGFloat.pi / 4
        let angle = (atan2(dy, dx) / step).rounded() * step
        let length = hypot(dx, dy)
        return CGPoint(x: a.x + cos(angle) * length, y: a.y + sin(angle) * length)
    }

    /// Turns the rect a→b into a square (side = larger dimension), keeping the drag direction.
    public static func constrainSquare(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let side = max(abs(dx), abs(dy))
        return CGPoint(x: a.x + (dx < 0 ? -side : side), y: a.y + (dy < 0 ? -side : side))
    }

    /// The two back corners of an arrow head pointing at `b`.
    public static func arrowHead(from a: CGPoint, to b: CGPoint, length: CGFloat, spread: CGFloat = .pi / 7) -> (CGPoint, CGPoint) {
        let theta = atan2(b.y - a.y, b.x - a.x)
        return (
            CGPoint(x: b.x - length * cos(theta - spread), y: b.y - length * sin(theta - spread)),
            CGPoint(x: b.x - length * cos(theta + spread), y: b.y - length * sin(theta + spread))
        )
    }
}

/// Positions the toolbars around a selection: tools to the right, actions below.
public enum ToolbarLayout {
    public static func verticalOrigin(selection s: CGRect, size: CGSize, bounds b: CGRect, gap: CGFloat = 6) -> CGPoint {
        let y = min(max(s.maxY - size.height, b.minY), b.maxY - size.height)
        if s.maxX + gap + size.width <= b.maxX { return CGPoint(x: s.maxX + gap, y: y) }
        if s.minX - gap - size.width >= b.minX { return CGPoint(x: s.minX - gap - size.width, y: y) }
        return CGPoint(x: max(b.minX, s.maxX - gap - size.width), y: y)
    }

    public static func horizontalOrigin(selection s: CGRect, size: CGSize, bounds b: CGRect, gap: CGFloat = 6) -> CGPoint {
        let x = min(max(s.maxX - size.width, b.minX), b.maxX - size.width)
        if s.maxY + gap + size.height <= b.maxY { return CGPoint(x: x, y: s.maxY + gap) }
        if s.minY - gap - size.height >= b.minY { return CGPoint(x: x, y: s.minY - gap - size.height) }
        return CGPoint(x: x, y: max(b.minY, s.maxY - gap - size.height))
    }
}
