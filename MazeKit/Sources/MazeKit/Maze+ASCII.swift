// Maze+ASCII -- text rendering of a Maze.
//
// Useful for debugging, command-line tools, golden-fixture tests,
// and any "I want to see this maze right now" use case where the
// SwiftUI / Canvas renderer is overkill.
//
// Format:
//   '#'  wall
//   ' '  path
//   '*'  cell on the solution path (when showSolution: true and the
//        Maze has a non-nil solution)
//
// Output is the maze including its perimeter walls but excluding the
// sentinel border the engine uses internally for bounds-free
// neighbor lookups. Each row ends with a newline; the last line is
// also newline-terminated.

import Foundation

extension Maze {
    public func asciiRender(showSolution: Bool = true) -> String {
        let solSet: Set<Coord> = Set((showSolution ? solution : nil) ?? [])
        let renderRows = 2 * height + 1
        let renderCols = 2 * width  + 1

        var out = ""
        out.reserveCapacity((renderCols + 1) * renderRows)

        for r in 1...renderRows {
            for c in 1...renderCols {
                let v = grid[r][c]
                if v != 0 {
                    out.append("#")
                } else if r.isMultiple(of: 2), c.isMultiple(of: 2) {
                    let coord = Coord(x: (c - 2) / 2, y: (r - 2) / 2)
                    out.append(solSet.contains(coord) ? "*" : " ")
                } else {
                    out.append(" ")
                }
            }
            out.append("\n")
        }
        return out
    }
}
