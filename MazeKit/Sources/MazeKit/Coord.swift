// Coord -- 2D integer cell coordinate inside a maze.
//
// Convention: x is horizontal (column, 0..<width, increasing rightward),
// y is vertical (row, 0..<height, increasing downward). This matches
// screen / SwiftUI coordinates and makes the API obvious for renderers.
//
// The engine internally uses raw "doubled" grid coordinates (cells at
// even positions, walls at odd positions, with a sentinel border) -- a
// faithful port of maze.c. That representation is private; only `Coord`
// is exposed publicly.

public struct Coord: Hashable, Sendable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

extension Coord: CustomStringConvertible {
    public var description: String { "(\(x),\(y))" }
}

/// Cardinal directions in screen-coordinate space:
///   x grows right, y grows down.
public enum Direction: Int, Sendable, CaseIterable {
    case up    = 0
    case down  = 1
    case left  = 2
    case right = 3

    /// One-cell step in this direction as (dx, dy).
    public var step: (dx: Int, dy: Int) {
        switch self {
        case .up   : return ( 0, -1)
        case .down : return ( 0,  1)
        case .left : return (-1,  0)
        case .right: return ( 1,  0)
        }
    }

    public var opposite: Direction {
        switch self {
        case .up   : return .down
        case .down : return .up
        case .left : return .right
        case .right: return .left
        }
    }
}
