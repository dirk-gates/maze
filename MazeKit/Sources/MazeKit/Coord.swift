// Coord -- 2D integer coordinate inside a maze grid.
//
// The maze grid in MazeKit follows the same convention as the C reference:
// the underlying storage is (2*height + 3) by (2*width + 3) cells where
// odd coordinates are "cells" the player can occupy and even coordinates
// are walls / wall-junctions. A border row/column on each side is always
// PATH so that the algorithm's neighbor-lookup never falls off the edge.
//
// Coord is used both for cell coordinates and for raw grid coordinates
// inside the engine. Public API surfaces Coord in cell-space (0-indexed,
// 0..<width and 0..<height); internal code that needs raw grid space uses
// `gridX = 2*(x+1)` and `gridY = 2*(y+1)`.

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

// Cardinal directions used by the carve and solve loops. Order matches
// maze.c's std_direction array so port-time fidelity is easier to verify.
public enum Direction: Int, Sendable, CaseIterable {
    case down  = 0
    case up    = 1
    case right = 2
    case left  = 3

    /// Cell-space step (delta_x, delta_y) for this direction.
    public var step: (dx: Int, dy: Int) {
        switch self {
        case .down : return ( 1,  0)
        case .up   : return (-1,  0)
        case .right: return ( 0,  1)
        case .left : return ( 0, -1)
        }
    }

    public var opposite: Direction {
        switch self {
        case .down : return .up
        case .up   : return .down
        case .right: return .left
        case .left : return .right
        }
    }
}
