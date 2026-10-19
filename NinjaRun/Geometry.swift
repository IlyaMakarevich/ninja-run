import CoreGraphics

/// Tile size in world units and level dimensions (in tiles).
let TS: CGFloat = 24
let COLS = 31
let ROWS = 23

// MARK: - Vector helpers (CGPoint is used as a 2D vector)

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
    static func += (a: inout CGPoint, b: CGPoint) { a = a + b }
    var length: CGFloat { hypot(x, y) }
    func dot(_ o: CGPoint) -> CGFloat { x * o.x + y * o.y }
    var normalized: CGPoint {
        let l = length
        return l > 1e-9 ? self * (1 / l) : .zero
    }
    func distance(to o: CGPoint) -> CGFloat { (self - o).length }
}

func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }

/// Distance from point `p` to segment `a`–`b`.
func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let ab = b - a
    let len2 = ab.dot(ab)
    if len2 < 1e-9 { return p.distance(to: a) }
    let t = clamp((p - a).dot(ab) / len2, 0, 1)
    return p.distance(to: a + ab * t)
}

// MARK: - Tiles

enum Tile: Equatable {
    case empty
    case full
    case slopeUp      // '/'  filled bottom-right, surface rises to the right
    case slopeDown    // '\'  filled bottom-left, surface falls to the right
    case ceilRight    // '7'  filled top-right
    case ceilLeft     // 'p'  filled top-left
    case door         // 'D'  solid until all keys are collected

    init(char: Character) {
        switch char {
        case "#": self = .full
        case "/": self = .slopeUp
        case "\\": self = .slopeDown
        case "7": self = .ceilRight
        case "p": self = .ceilLeft
        case "D": self = .door
        default: self = .empty
        }
    }

    /// Convex polygon in unit tile coordinates, counter-clockwise, y up.
    var unitPolygon: [CGPoint]? {
        switch self {
        case .empty: return nil
        case .full, .door: return [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        case .slopeUp: return [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1)]
        case .slopeDown: return [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1)]
        case .ceilRight: return [CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        case .ceilLeft: return [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        }
    }
}

/// Closest point on the boundary of a CCW convex polygon, and whether `p` lies inside.
func closestOnPolygon(_ poly: [CGPoint], _ p: CGPoint) -> (point: CGPoint, inside: Bool) {
    var inside = true
    var best = CGPoint.zero
    var bestD = CGFloat.greatestFiniteMagnitude
    for i in 0..<poly.count {
        let a = poly[i], b = poly[(i + 1) % poly.count]
        let ab = b - a
        if ab.x * (p.y - a.y) - ab.y * (p.x - a.x) < 0 { inside = false }
        let t = clamp((p - a).dot(ab) / ab.dot(ab), 0, 1)
        let q = a + ab * t
        let d = q.distance(to: p)
        if d < bestD { bestD = d; best = q }
    }
    return (best, inside)
}

// MARK: - Level map

struct Spawn {
    let kind: Character
    let col: Int
    let row: Int   // counted from the bottom
    var center: CGPoint { CGPoint(x: (CGFloat(col) + 0.5) * TS, y: (CGFloat(row) + 0.5) * TS) }
}

final class LevelMap {
    private(set) var tiles: [[Tile]]   // [row from bottom][col]
    var doorsOpen = false
    private(set) var spawns: [Spawn] = []

    init(map: String) {
        var lines = map.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        lines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        while lines.count < ROWS { lines.append("") }
        tiles = Array(repeating: Array(repeating: .empty, count: COLS), count: ROWS)
        for (r, line) in lines.prefix(ROWS).enumerated() {
            let y = ROWS - 1 - r
            let chars = Array(line)
            for x in 0..<COLS {
                let ch: Character = x < chars.count ? chars[x] : "."
                let tile = Tile(char: ch)
                tiles[y][x] = tile
                if tile == .empty, ch != ".", ch != " " {
                    spawns.append(Spawn(kind: ch, col: x, row: y))
                }
            }
        }
    }

    var worldSize: CGSize { CGSize(width: CGFloat(COLS) * TS, height: CGFloat(ROWS) * TS) }

    /// Tile at a grid cell; anything outside the level is solid.
    func tile(_ x: Int, _ y: Int) -> Tile {
        guard x >= 0, x < COLS, y >= 0, y < ROWS else { return .full }
        let t = tiles[y][x]
        if t == .door && doorsOpen { return .empty }
        return t
    }

    func cell(of p: CGPoint) -> (x: Int, y: Int) {
        (Int(floor(p.x / TS)), Int(floor(p.y / TS)))
    }

    func isOpenCell(_ x: Int, _ y: Int) -> Bool { tile(x, y) == .empty }

    func polygon(_ x: Int, _ y: Int) -> [CGPoint]? {
        guard let unit = tile(x, y).unitPolygon else { return nil }
        let ox = CGFloat(x) * TS, oy = CGFloat(y) * TS
        return unit.map { CGPoint(x: ox + $0.x * TS, y: oy + $0.y * TS) }
    }

    func isSolid(_ p: CGPoint) -> Bool {
        let c = cell(of: p)
        guard let poly = polygon(c.x, c.y) else { return false }
        return closestOnPolygon(poly, p).inside
    }

    /// Pushes a circle out of the geometry. Returns the contact normals (pointing away from walls).
    func collideCircle(_ c: inout CGPoint, radius r: CGFloat) -> [CGPoint] {
        var normals: [CGPoint] = []
        for _ in 0..<3 {
            var moved = false
            let x0 = Int(floor((c.x - r) / TS)), x1 = Int(floor((c.x + r) / TS))
            let y0 = Int(floor((c.y - r) / TS)), y1 = Int(floor((c.y + r) / TS))
            for ty in y0...y1 {
                for tx in x0...x1 {
                    guard let poly = polygon(tx, ty) else { continue }
                    let (cp, inside) = closestOnPolygon(poly, c)
                    let d = c - cp
                    let dist = d.length
                    guard dist > 1e-6 else { continue }
                    let n: CGPoint
                    let push: CGFloat
                    if inside {
                        n = d * (-1 / dist)
                        push = r + dist
                    } else {
                        guard dist < r else { continue }
                        n = d * (1 / dist)
                        push = r - dist
                    }
                    c += n * push
                    normals.append(n)
                    moved = true
                }
            }
            if !moved { break }
        }
        return normals
    }

    /// Distance along `dir` (normalized) until geometry is hit, capped at `maxDist`.
    func raycast(from a: CGPoint, dir: CGPoint, maxDist: CGFloat) -> CGFloat {
        var t: CGFloat = 0
        while t < maxDist {
            if isSolid(a + dir * t) { return t }
            t += 2
        }
        return maxDist
    }

    func lineOfSight(_ a: CGPoint, _ b: CGPoint) -> Bool {
        let d = b - a
        let len = d.length
        return raycast(from: a, dir: d.normalized, maxDist: len) >= len
    }

    /// One combined path for all static solid tiles (doors are drawn separately).
    func staticTilesPath() -> CGPath {
        let path = CGMutablePath()
        for y in 0..<ROWS {
            for x in 0..<COLS {
                let t = tiles[y][x]
                guard t != .door, let poly = polygon(x, y) else { continue }
                path.addLines(between: poly)
                path.closeSubpath()
            }
        }
        return path
    }
}
