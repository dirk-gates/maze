// PropertyTests -- correctness invariants the engine must satisfy
// for every (seed, size, lookAhead) combination.

import Testing
@testable import MazeKit

@Suite("Generator properties")
struct PropertyTests {

    // ----- helpers -----

    static func generate(width: Int, height: Int,
                         seed: UInt64, lookAhead: Int = 0) async -> Maze {
        let p = GeneratorParameters(width: width, height: height,
                                    lookAheadDepth: lookAhead, seed: seed)
        let g = Generator(p)
        var final: Maze?
        for await event in g.generate() {
            if case .finished(let m) = event { final = m }
        }
        return final!
    }

    /// BFS over PATH cells to verify connectivity from `start`.
    static func reachableCells(in maze: Maze, from start: Coord) -> Set<Coord> {
        var visited: Set<Coord> = []
        var queue: [Coord] = [start]
        visited.insert(start)
        while let c = queue.popLast() {
            for d in Direction.allCases {
                let n = Coord(x: c.x + d.step.dx, y: c.y + d.step.dy)
                guard n.x >= 0, n.x < maze.width,
                      n.y >= 0, n.y < maze.height else { continue }
                if visited.contains(n) { continue }
                if maze.cell(n) == .wall { continue }
                if maze.wall(between: c, n) { continue }
                visited.insert(n)
                queue.append(n)
            }
        }
        return visited
    }

    // ----- the actual tests -----

    @Test("Every cell is .path -- the doubled-grid representation only stores walls between cells")
    func everyCellIsPath() async {
        let maze = await Self.generate(width: 10, height: 8, seed: 1)
        for y in 0..<maze.height {
            for x in 0..<maze.width {
                #expect(maze.cell(Coord(x: x, y: y)) == .path,
                        "cell at (\(x),\(y)) was \(maze.cell(Coord(x: x, y: y)))")
            }
        }
    }

    @Test("Every cell is reachable from the entrance side",
          arguments: [(10, 5), (15, 10), (20, 12), (8, 8)])
    func everyCellReachable(size: (Int, Int)) async {
        let (w, h) = size
        let maze   = await Self.generate(width: w, height: h, seed: UInt64(w * 31 + h))
        let start  = Coord(x: maze.entrance.x, y: 0)
        let reached = Self.reachableCells(in: maze, from: start)
        let expected = w * h
        #expect(reached.count == expected,
                "only \(reached.count) / \(expected) cells reachable in \(w)x\(h)")
    }

    @Test("Solution path connects entrance edge to exit edge",
          arguments: [(10, 5), (15, 10), (20, 12)])
    func solutionConnects(size: (Int, Int)) async {
        let (w, h) = size
        let maze   = await Self.generate(width: w, height: h, seed: UInt64(w * 17 + h))
        guard let path = maze.solution, !path.isEmpty else {
            Issue.record("no solution computed for \(w)x\(h)")
            return
        }
        // First cell is at row 0 (top of grid) -- the entrance opens above.
        // Last cell is at row height-1 -- the exit opens below.
        #expect(path.first?.y == 0,                  "path doesn't start at top row")
        #expect(path.last?.y  == h - 1,              "path doesn't end at bottom row")
        // Every consecutive pair must be adjacent and have no wall between them.
        for i in 0..<(path.count - 1) {
            let a = path[i], b = path[i + 1]
            let dx = abs(a.x - b.x), dy = abs(a.y - b.y)
            #expect(dx + dy == 1, "path step (\(a))->(\(b)) is not a 4-neighbor move")
            #expect(maze.wall(between: a, b) == false,
                    "path step (\(a))->(\(b)) crosses a wall")
        }
    }

    @Test("Same seed produces same maze (determinism)")
    func deterministicSeed() async {
        let a = await Self.generate(width: 12, height: 8, seed: 42)
        let b = await Self.generate(width: 12, height: 8, seed: 42)
        #expect(a.entrance == b.entrance)
        #expect(a.exit     == b.exit)
        #expect(a.solution == b.solution)
        // Compare cell-by-cell wall structure.
        for y in 0..<a.height {
            for x in 0..<a.width {
                let c = Coord(x: x, y: y)
                for n in [Coord(x: x + 1, y: y), Coord(x: x, y: y + 1)] {
                    guard n.x < a.width, n.y < a.height else { continue }
                    #expect(a.wall(between: c, n) == b.wall(between: c, n),
                            "wall structure diverges at (\(c)..\(n))")
                }
            }
        }
    }

    @Test("Different seeds produce different mazes (probably)")
    func differentSeedsDiffer() async {
        let a = await Self.generate(width: 12, height: 8, seed: 1)
        let b = await Self.generate(width: 12, height: 8, seed: 2)
        #expect(a.solution != b.solution || a.entrance != b.entrance,
                "two different seeds produced an identical maze (statistically very unlikely)")
    }

    @Test("Look-ahead produces valid mazes")
    func lookAheadProducesValidMaze() async {
        let maze = await Self.generate(width: 15, height: 10, seed: 7, lookAhead: 4)
        let reached = Self.reachableCells(in: maze, from: Coord(x: maze.entrance.x, y: 0))
        #expect(reached.count == 15 * 10)
        #expect(maze.solution != nil)
    }

    @Test("Tile lookup is valid for every cell")
    func tileLookupValid() async {
        let maze = await Self.generate(width: 10, height: 6, seed: 3)
        for y in 0..<maze.height {
            for x in 0..<maze.width {
                _ = maze.tile(at: Coord(x: x, y: y))   // must not crash
            }
        }
    }

    @Test("minPathLength produces a maze meeting the threshold")
    func minPathLengthSatisfied() async {
        // Ask for at least half the cells on the solution path.
        // Best-opening search picks the longest, so meeting 50% is
        // very achievable -- typical first attempts already exceed it.
        let p = GeneratorParameters(
            width             : 12,
            height            : 8,
            lookAheadDepth    : 0,
            minPathLength     : 12 * 8 / 2,
            seed              : 1
        )
        var attemptCount = 0
        var finalLen     = 0
        for await event in Generator(p).generate() {
            switch event {
            case .attempt:
                attemptCount += 1
            case .finished(let m):
                finalLen = m.solution?.count ?? 0
            default: break
            }
        }
        #expect(attemptCount >= 1)
        #expect(finalLen >= p.minPathLength!,
                "got path length \(finalLen) after \(attemptCount) attempts")
    }
}
