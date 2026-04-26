// WallTile -- 16-entry enum mirroring maze.c's `output_lookup` table.
//
// At every wall-coordinate (even-indexed) cell, the renderer wants to
// know which combination of cardinal-neighbor walls is present so it
// can pick the right glyph / sprite / 3D segment. The bitmask is:
//
//     bit 0 -- north wall present
//     bit 1 -- east  wall present
//     bit 2 -- south wall present
//     bit 3 -- west  wall present
//
// Used for 2D rendering today, will reuse the same lookup for 3D
// segment selection (corner vs. straight vs. T-intersection mesh).

public enum WallTile: Int, Sendable, CaseIterable {
    case blank        = 0    // 0000 -- no walls
    case north        = 1    // 0001
    case east         = 2    // 0010
    case northEast    = 3    // 0011 -- L bottom-left
    case south        = 4    // 0100
    case northSouth   = 5    // 0101 -- vertical
    case eastSouth    = 6    // 0110 -- L top-left
    case teaWest      = 7    // 0111 -- T pointing west
    case west         = 8    // 1000
    case northWest    = 9    // 1001 -- L bottom-right
    case eastWest     = 10   // 1010 -- horizontal
    case teaSouth     = 11   // 1011 -- T pointing south
    case southWest    = 12   // 1100 -- L top-right
    case teaEast      = 13   // 1101 -- T pointing east
    case teaNorth     = 14   // 1110 -- T pointing north
    case intersection = 15   // 1111 -- 4-way

    /// Build a tile from individual neighbor-wall flags.
    public static func from(north: Bool, east: Bool, south: Bool, west: Bool) -> WallTile {
        let mask = (north ? 1 : 0)
                 | (east  ? 2 : 0)
                 | (south ? 4 : 0)
                 | (west  ? 8 : 0)
        return WallTile(rawValue: mask)!
    }
}
