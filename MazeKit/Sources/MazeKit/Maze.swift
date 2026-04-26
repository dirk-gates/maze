// Maze -- immutable, fully-built maze. Produced by Generator.generate().
//
// Coordinates exposed via the public API are cell-space:
//   x in 0..<width, y in 0..<height
// where (0, 0) is the top-left cell. Internal storage uses the
// (2*height + 3) by (2*width + 3) raw grid from the C port; the public
// methods translate to/from raw grid coordinates as needed.

public struct Maze: Sendable {
    public let width: Int
    public let height: Int

    /// Top-edge entrance and bottom-edge exit, in cell-space.
    public let entrance: Coord
    public let exit: Coord

    /// Solved path from entrance to exit, in cell-space. nil if not yet solved.
    public internal(set) var solution: [Coord]?

    // ----- internal raw-grid storage -----

    /// Raw grid: (2*height + 3) rows by (2*width + 3) columns.
    /// 0 = path, 1 = wall. Solver-time states are not retained here.
    @usableFromInline
    let grid: [[UInt8]]

    @usableFromInline
    init(width: Int, height: Int, entrance: Coord, exit: Coord, grid: [[UInt8]]) {
        self.width    = width
        self.height   = height
        self.entrance = entrance
        self.exit     = exit
        self.solution = nil
        self.grid     = grid
    }

    // ----- public queries -----

    public func cell(_ c: Coord) -> CellKind {
        let r = 2 * (c.x + 1)
        let k = 2 * (c.y + 1)
        return grid[r][k] == 0 ? .path : .wall
    }

    /// True if there is a wall between adjacent cells `a` and `b`.
    /// `a` and `b` must be 4-neighbor adjacent (differ by 1 in exactly one axis).
    public func wall(between a: Coord, _ b: Coord) -> Bool {
        let r1 = 2 * (a.x + 1), k1 = 2 * (a.y + 1)
        let r2 = 2 * (b.x + 1), k2 = 2 * (b.y + 1)
        let mr = (r1 + r2) / 2
        let mk = (k1 + k2) / 2
        return grid[mr][mk] != 0
    }

    /// WallTile at a given wall-coordinate (used by renderers).
    public func tile(at c: Coord) -> WallTile {
        // Cell-space (x, y) in 0..<width, 0..<height -- but tiles are
        // really at wall-junction coordinates. We expose this in the
        // same cell-space the rest of the API uses; the renderer
        // walks all cells and reads wall membership of the four edges.
        let r = 2 * (c.x + 1)
        let k = 2 * (c.y + 1)
        return WallTile.from(
            north: r > 0                  && grid[r - 1][k] != 0,
            east : k + 1 < grid[r].count  && grid[r][k + 1] != 0,
            south: r + 1 < grid.count     && grid[r + 1][k] != 0,
            west : k > 0                  && grid[r][k - 1] != 0
        )
    }
}
