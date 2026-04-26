// Maze -- immutable, fully-built maze. Produced by Generator.generate().
//
// Public coordinates are cell-space:
//   x in 0..<width  (column, increasing rightward)
//   y in 0..<height (row,    increasing downward)
//
// Internal storage uses a "doubled" grid (rows 0..2*height+2, cols
// 0..2*width+2) where odd indices are cells and even indices are walls,
// with a sentinel PATH border to keep neighbor-lookups in-bounds.
// Conversion: row = 2*(y + 1), col = 2*(x + 1).

public struct Maze: Sendable {
    public let width: Int
    public let height: Int

    /// Top-edge gate (entrance) and bottom-edge gate (exit), in cell-space.
    /// y = -1 for entrance and y = height for exit -- they sit *outside*
    /// the cell grid, on the border, so renderers can draw the gap.
    public let entrance: Coord
    public let exit: Coord

    /// Solved path from entrance to exit, in cell-space. nil until solved.
    public internal(set) var solution: [Coord]?

    // ----- internal raw-grid storage -----

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
        let row = 2 * (c.y + 1)
        let col = 2 * (c.x + 1)
        return grid[row][col] == 0 ? .path : .wall
    }

    /// True if there is a wall between adjacent cells `a` and `b`.
    /// `a` and `b` must be 4-neighbor adjacent (differ by 1 in one axis).
    public func wall(between a: Coord, _ b: Coord) -> Bool {
        let r1 = 2 * (a.y + 1), c1 = 2 * (a.x + 1)
        let r2 = 2 * (b.y + 1), c2 = 2 * (b.x + 1)
        let mr = (r1 + r2) / 2
        let mc = (c1 + c2) / 2
        return grid[mr][mc] != 0
    }

    /// WallTile at the given cell, computed from the four neighbor walls.
    public func tile(at c: Coord) -> WallTile {
        let row = 2 * (c.y + 1)
        let col = 2 * (c.x + 1)
        return WallTile.from(
            north: row > 0                  && grid[row - 1][col] != 0,
            east : col + 1 < grid[row].count && grid[row][col + 1] != 0,
            south: row + 1 < grid.count     && grid[row + 1][col] != 0,
            west : col > 0                  && grid[row][col - 1] != 0
        )
    }
}
