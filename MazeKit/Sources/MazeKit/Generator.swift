// Generator -- maze generator. Faithful port of maze.c Rev 1.6:
// random-walk path carving, recursive variable-depth look-ahead,
// 1x1 orphan elimination, mid-wall-opening push, and best-opening
// search via embedded solving.
//
// The public `Generator` actor wraps an internal `GeneratorEngine`
// struct that holds all the algorithmic state and emits events into
// the AsyncStream's continuation as it goes.

import Foundation

public actor Generator {
    private let params: GeneratorParameters

    public init(_ params: GeneratorParameters) {
        precondition(params.width  > 0, "width must be positive")
        precondition(params.height > 0, "height must be positive")
        self.params = params
    }

    /// Begin generation. Returns a stream of GenerationEvents.
    /// The final event is always `.finished(Maze)`.
    ///
    /// If `minPathLength` is set, the Generator may regenerate one or
    /// more times until a maze whose solution meets the threshold is
    /// produced (or `maxAttempts` is reached, in which case the longest
    /// attempt found is returned). Each attempt is announced with an
    /// `.attempt(n)` event so renderers can clear and re-animate.
    public nonisolated func generate() -> AsyncStream<GenerationEvent> {
        AsyncStream { continuation in
            let params = self.params
            Task.detached(priority: .userInitiated) {
                let target = params.minPathLength ?? 0
                var best     : Maze? = nil
                var bestLen  : Int   = -1

                for attempt in 1...max(1, params.maxAttempts) {
                    continuation.yield(.attempt(attempt))

                    // Derive a fresh seed each attempt so we don't keep
                    // generating the same maze when the first didn't
                    // satisfy minPathLength.
                    var attemptParams = params
                    if let s = params.seed {
                        attemptParams.seed = s &+ UInt64(attempt - 1)
                    }

                    var engine = GeneratorEngine(params: attemptParams,
                                                 continuation: continuation)
                    let maze = engine.run()
                    let len  = maze.solution?.count ?? 0

                    if len > bestLen {
                        bestLen = len
                        best    = maze
                    }
                    if len >= target {
                        break
                    }
                }

                if let m = best {
                    continuation.yield(.finished(m))
                }
                continuation.finish()
            }
        }
    }
}

// ========================================================================
// MARK: - Internal engine
// ========================================================================

/// Cell-state codes used in the raw grid. UInt8 keeps the grid compact.
@usableFromInline let cellPath  : UInt8 = 0
@usableFromInline let cellWall  : UInt8 = 1
@usableFromInline let cellSolved: UInt8 = 2
@usableFromInline let cellTried : UInt8 = 3

/// One cardinal step in raw-grid units (raw cells are 2 apart).
private struct GridStep {
    let dRow: Int
    let dCol: Int
}

private let cardinalSteps: [GridStep] = [
    GridStep(dRow:  2, dCol:  0),   // south (down)
    GridStep(dRow: -2, dCol:  0),   // north (up)
    GridStep(dRow:  0, dCol:  2),   // east  (right)
    GridStep(dRow:  0, dCol: -2),   // west  (left)
]

/// Internal carving + solving state. One-shot: created, run(), then dropped.
struct GeneratorEngine {
    let params: GeneratorParameters
    let continuation: AsyncStream<GenerationEvent>.Continuation
    var rng: SplitMix64

    /// Doubled grid: (2*height + 3) rows by (2*width + 3) cols.
    /// Borders are kept at .path as sentinels so neighbor-lookups never
    /// fall off the grid.
    var grid: [[UInt8]]
    let maxRow: Int     // = 2*(height + 1) + 1
    let maxCol: Int     // = 2*(width  + 1) + 1
    let begRow: Int     // = 2 (entrance is at row 1)
    let endRow: Int     // = 2*height (exit is at row endRow + 1)
    var begCol: Int = 0
    var endCol: Int = 0

    /// Set of "currently being probed by look-ahead" raw-grid cells.
    /// Replaces maze.c's CHECK marker without polluting the grid.
    var visiting: Set<Int> = []

    /// Look-ahead budget (decays during retry loops in find_path_start).
    var pathDepth: Int = 0

    /// Statistics — emitted in events / used by best-opening selection.
    var numPaths: Int = 0
    var numWallPushes: Int = 0
    var maxChecks: Int = 0
    var pathLen: Int = 0
    var turnCount: Int = 0
    var maxPathLength: Int = 0
    var numSolves: Int = 0
    var maxLookDepth: Int = 0

    /// Cap on look-ahead recursion (matches maze.c's 500K).
    let maxChecksPerCall: Int

    init(params: GeneratorParameters, continuation: AsyncStream<GenerationEvent>.Continuation) {
        self.params       = params
        self.continuation = continuation
        if let s = params.seed {
            self.rng = SplitMix64(seed: s)
        } else {
            var sys = SystemRandomNumberGenerator()
            self.rng = SplitMix64(seed: sys.next())
        }
        self.maxRow = 2 * (params.height + 1) + 1
        self.maxCol = 2 * (params.width  + 1) + 1
        self.begRow = 2
        self.endRow = 2 * params.height
        self.maxChecksPerCall = params.maxLookAheadChecks
        self.grid = Array(repeating: Array(repeating: cellWall, count: maxCol),
                          count: maxRow)
    }

    // ------------------------------------------------------------------
    // MARK: - Top-level orchestration
    // ------------------------------------------------------------------

    /// Run one generation attempt. Returns the resulting Maze. Emits
    /// every event except `.finished` (the outer loop in
    /// `Generator.generate()` is responsible for emitting `.finished`
    /// once, on the kept attempt).
    mutating func run() -> Maze {
        var (row, col) = initializeGrid()
        carvePath(row: &row, col: &col)
        while let (r, c) = findPathStart() {
            row = r; col = c
            carvePath(row: &row, col: &col)
        }
        while pushMidWallOpenings() > 0 { /* keep pushing until stable */ }
        searchBestOpenings(row: &row, col: &col)

        // Capture the solution discovered while picking gates, then clear
        // solver markers from the grid so the public Maze contains only
        // .path/.wall.
        let solution = currentSolutionPath()
        restoreSolverMarkers()

        let entrance = Coord(x: (begCol - 2) / 2, y: -1)
        let exit     = Coord(x: (endCol - 2) / 2, y: params.height)
        var maze = Maze(
            width   : params.width,
            height  : params.height,
            entrance: entrance,
            exit    : exit,
            grid    : grid
        )
        maze.solution = solution

        continuation.yield(.gates(entrance: entrance, exit: exit))
        return maze
    }

    // ------------------------------------------------------------------
    // MARK: - Grid setup
    // ------------------------------------------------------------------

    /// Set every interior cell to .wall, keep the border at .path as
    /// sentinels, and return a random starting cell coordinate (raw grid).
    mutating func initializeGrid() -> (Int, Int) {
        for r in 1..<(maxRow - 1) {
            for c in 1..<(maxCol - 1) {
                grid[r][c] = cellWall
            }
        }
        // Sentinel borders (already .path from init, but be explicit).
        for r in 0..<maxRow {
            grid[r][0] = cellPath
            grid[r][2 * (params.width + 1)] = cellPath
        }
        for c in 0..<maxCol {
            grid[0][c] = cellPath
            grid[2 * (params.height + 1)][c] = cellPath
        }
        let startRow = 2 * (rng.nextInt(below: params.height) + 1)
        let startCol = 2 * (rng.nextInt(below: params.width)  + 1)
        return (startRow, startCol)
    }

    // ------------------------------------------------------------------
    // MARK: - Cell read / write helpers
    // ------------------------------------------------------------------

    /// Encode (row, col) as a single Int for the visiting set.
    @inline(__always)
    private func encode(_ row: Int, _ col: Int) -> Int {
        row * maxCol + col
    }

    /// Read a cell with look-ahead "in-progress" cells masked out.
    /// A cell currently being probed by look-ahead reports as != val for
    /// any val. This replaces maze.c's temporary CHECK marker without
    /// polluting the grid.
    @inline(__always)
    private func cellIs(_ row: Int, _ col: Int, _ val: UInt8) -> Bool {
        if visiting.contains(encode(row, col)) { return false }
        return grid[row][col] == val
    }

    /// Write a cell and emit a public event when appropriate.
    /// Distinguishes three position types in the doubled grid:
    ///   even row + even col: a cell. Emits .carved on wall->path.
    ///   even row + odd col : a vertical wall slot. Emits .opened/.closed.
    ///   odd row + even col : a horizontal wall slot. Same.
    ///   odd row + odd col  : a wall corner. No events (always wall).
    private mutating func setCell(_ row: Int, _ col: Int, _ val: UInt8) {
        guard grid[row][col] != val else { return }
        grid[row][col] = val

        let rowEven = row.isMultiple(of: 2)
        let colEven = col.isMultiple(of: 2)

        if rowEven, colEven {
            if val == cellPath {
                continuation.yield(.carved(toCellCoord(row: row, col: col)))
            }
        } else if rowEven != colEven, let edge = wallSlotEdge(row: row, col: col) {
            if val == cellPath {
                continuation.yield(.opened(edge))
            } else if val == cellWall {
                continuation.yield(.closed(edge))
            }
        }
    }

    /// Translate a wall-slot raw-grid position to an Edge between the
    /// two cell-space Coords on either side. Returns nil if the slot
    /// is on the maze perimeter (one side would be outside the maze).
    private func wallSlotEdge(row: Int, col: Int) -> Edge? {
        if row.isMultiple(of: 2), !col.isMultiple(of: 2) {
            // Vertical wall: between cells (col-3)/2 and (col-1)/2 at y=(row-2)/2
            let cellY  = (row - 2) / 2
            let cellX1 = (col - 3) / 2
            let cellX2 = (col - 1) / 2
            guard cellX1 >= 0, cellX2 < params.width,
                  cellY  >= 0, cellY  < params.height else { return nil }
            return Edge(Coord(x: cellX1, y: cellY),
                        Coord(x: cellX2, y: cellY))
        } else if !row.isMultiple(of: 2), col.isMultiple(of: 2) {
            // Horizontal wall: between cells (row-3)/2 and (row-1)/2 at x=(col-2)/2
            let cellX  = (col - 2) / 2
            let cellY1 = (row - 3) / 2
            let cellY2 = (row - 1) / 2
            guard cellY1 >= 0, cellY2 < params.height,
                  cellX  >= 0, cellX  < params.width else { return nil }
            return Edge(Coord(x: cellX, y: cellY1),
                        Coord(x: cellX, y: cellY2))
        }
        return nil
    }

    /// Convert raw grid coordinates to public cell-space Coord.
    @inline(__always)
    private func toCellCoord(row: Int, col: Int) -> Coord {
        Coord(x: (col - 2) / 2, y: (row - 2) / 2)
    }

    // ------------------------------------------------------------------
    // MARK: - Look-ahead & orphan checks  (port of maze.c lines 232..276)
    // ------------------------------------------------------------------

    /// Recursively check that a path of `depth` cells can be carved or
    /// traced from (row, col). Returns true if it can. Mirrors
    /// maze.c::check_directions exactly.
    private mutating func checkDirections(row: Int, col: Int, val: UInt8,
                                          depth: Int, checks: inout Int) -> Bool {
        guard depth > 0, checks < maxChecksPerCall else { return true }
        checks += 1
        if maxChecks < checks { maxChecks = checks }
        if depth > maxLookDepth { maxLookDepth = depth }

        let key = encode(row, col)
        visiting.insert(key)
        defer { visiting.remove(key) }

        // Emit a "considering" event for visualization; rate is bounded
        // by maxChecksPerCall so this can't flood the stream.
        continuation.yield(.considering(toCellCoord(row: row, col: col), depth: depth))

        // Try each cardinal direction; stop at the first that succeeds
        // (matches the short-circuit `||` chain in C).
        for step in cardinalSteps {
            let r1 = row + step.dRow / 2
            let c1 = col + step.dCol / 2
            let r2 = row + step.dRow
            let c2 = col + step.dCol
            if cellIs(r1, c1, val), cellIs(r2, c2, val),
               checkDirections(row: r2, col: c2, val: val,
                               depth: depth - 1, checks: &checks) {
                return true
            }
        }
        return false
    }

    /// True if (row, col) is a 1x1 path-cell completely walled off (4 walls)
    /// with paths beyond all 4 walls. Such a cell is a "stranded" 1x1 area
    /// the carver should avoid creating.
    private func orphan1x1(_ row: Int, _ col: Int) -> Bool {
        guard row >= 2, col >= 2,
              row + 2 < maxRow, col + 2 < maxCol else { return false }
        return grid[row - 1][col] == cellWall && grid[row - 2][col] == cellPath
            && grid[row + 1][col] == cellWall && grid[row + 2][col] == cellPath
            && grid[row][col - 1] == cellWall && grid[row][col - 2] == cellPath
            && grid[row][col + 1] == cellWall && grid[row][col + 2] == cellPath
    }

    /// Speculatively carve in (dRow, dCol) and check whether doing so
    /// would create a 1x1 orphan adjacent to the new path. Restores the
    /// walls before returning. Single-threaded port -- safe.
    private mutating func wouldCreateOrphan(row: Int, col: Int,
                                            dRow: Int, dCol: Int,
                                            depth: Int) -> Bool {
        guard depth > 0,
              row + dRow >= 2, col + dCol >= 2,
              row + dRow + 2 < maxRow, col + dCol + 2 < maxCol else {
            return false
        }
        let mr = row + dRow / 2
        let mc = col + dCol / 2
        let tr = row + dRow
        let tc = col + dCol
        guard grid[mr][mc] == cellWall, grid[tr][tc] == cellWall else { return false }

        grid[mr][mc] = cellPath
        grid[tr][tc] = cellPath
        defer {
            grid[mr][mc] = cellWall
            grid[tr][tc] = cellWall
        }

        return orphan1x1(tr - 2, tc    )
            || orphan1x1(tr + 2, tc    )
            || orphan1x1(tr,     tc - 2)
            || orphan1x1(tr,     tc + 2)
    }

    // ------------------------------------------------------------------
    // MARK: - Direction picking  (port of maze.c lines 278..339)
    // ------------------------------------------------------------------

    /// Test a single direction at (row, col) for viability.
    /// Returns the GridStep if usable, nil otherwise.
    private mutating func look(row: Int, col: Int, step: GridStep, val: UInt8,
                               depth: Int) -> GridStep? {
        let r1 = row + step.dRow / 2
        let c1 = col + step.dCol / 2
        let r2 = row + step.dRow
        let c2 = col + step.dCol
        guard r1 >= 0, c1 >= 0, r2 >= 0, c2 >= 0,
              r2 < maxRow, c2 < maxCol else { return nil }
        guard cellIs(r1, c1, val), cellIs(r2, c2, val) else { return nil }
        if val == cellWall, wouldCreateOrphan(row: row, col: col,
                                              dRow: step.dRow, dCol: step.dCol,
                                              depth: depth) {
            return nil
        }
        var checks = 0
        guard checkDirections(row: r2, col: c2, val: val,
                              depth: depth, checks: &checks) else { return nil }
        return step
    }

    /// Find all cardinal directions at (row, col) where we can advance.
    /// `searching` controls whether to apply the look-ahead heuristic
    /// (carving) vs. simple presence check (solving).
    private mutating func findDirections(row: Int, col: Int, val: UInt8,
                                         searching: Bool) -> [GridStep] {
        var results: [GridStep] = []
        var depth = searching ? pathDepth : 0
        repeat {
            for step in cardinalSteps {
                if let s = look(row: row, col: col, step: step,
                                val: val, depth: depth) {
                    results.append(s)
                }
            }
            // If carving and no direction worked, halve the look-ahead
            // budget and retry (matches maze.c's `path_depth--` retry).
            if !results.isEmpty || !searching || depth <= 0 { break }
            depth -= 1
        } while results.isEmpty && searching && depth >= 0
        if depth < 0 { pathDepth = 0 } else { pathDepth = depth }
        return results
    }

    /// True if (row, col) is a "straight-through" cell -- there is path
    /// on both sides in one axis. Such cells can't seed new branches.
    private func straightThru(_ row: Int, _ col: Int, _ val: UInt8) -> Bool {
        guard row >= 2, col >= 2,
              row + 2 < maxRow, col + 2 < maxCol else { return false }
        return (grid[row - 1][col] == val && grid[row - 2][col] == val
             && grid[row + 1][col] == val && grid[row + 2][col] == val)
            || (grid[row][col - 1] == val && grid[row][col - 2] == val
             && grid[row][col + 1] == val && grid[row][col + 2] == val)
    }

    /// Search for an existing PATH cell that has at least one wall
    /// neighbor and isn't a straight-through. Returns the first such
    /// found (scanning starts at a random offset).
    private mutating func findPathStart() -> (Int, Int)? {
        pathDepth = params.lookAheadDepth
        repeat {
            let xStart = rng.nextInt(below: params.height)
            let yStart = rng.nextInt(below: params.width)
            for i in 0..<params.height {
                for j in 0..<params.width {
                    let row = 2 * (((xStart + i) % params.height) + 1)
                    let col = 2 * (((yStart + j) % params.width)  + 1)
                    if grid[row][col] == cellPath,
                       !straightThru(row, col, cellPath),
                       !findDirections(row: row, col: col,
                                       val: cellWall, searching: false).isEmpty {
                        return (row, col)
                    }
                }
            }
            pathDepth -= 1
        } while pathDepth >= 0
        pathDepth = 0
        return nil
    }

    // ------------------------------------------------------------------
    // MARK: - Carving  (port of maze.c::carve_path)
    // ------------------------------------------------------------------

    private mutating func carvePath(row: inout Int, col: inout Int) {
        pathDepth = params.lookAheadDepth
        numPaths += 1
        setCell(row, col, cellPath)
        while true {
            let dirs = findDirections(row: row, col: col,
                                      val: cellWall, searching: true)
            if dirs.isEmpty { break }
            let step = dirs[rng.nextInt(below: dirs.count)]
            setCell(row + step.dRow / 2, col + step.dCol / 2, cellPath)
            row += step.dRow
            col += step.dCol
            setCell(row, col, cellPath)
        }
    }

    // ------------------------------------------------------------------
    // MARK: - Mid-wall opening push  (port of maze.c lines 467..495)
    // ------------------------------------------------------------------

    private func isMidWallOpening(_ row: Int, _ col: Int) -> Bool {
        guard row >= 1, col >= 1,
              row + 1 < maxRow, col + 1 < maxCol else { return false }
        return grid[row    ][col    ] == cellPath
            && grid[row - 1][col - 1] != cellWall
            && grid[row - 1][col + 1] != cellWall
            && grid[row + 1][col - 1] != cellWall
            && grid[row + 1][col + 1] != cellWall
    }

    /// Push every mid-wall opening one step right (if on a horizontal
    /// wall) or down (if on a vertical wall). Returns the number of
    /// pushes made; caller loops until stable. Mirrors maze.c.
    private mutating func pushMidWallOpenings() -> Int {
        var moves = 0
        for i in 1..<(2 * (params.height + 1)) {
            var j = (i & 1) + 1
            while j < 2 * (params.width + 1) {
                if isMidWallOpening(i, j) {
                    setCell(i, j, cellWall)
                    if (i & 1) == 1 {
                        let toC = j + 2
                        if toC < maxCol {
                            setCell(i, toC, cellPath)
                            continuation.yield(.pushed(
                                from: toCellCoord(row: i, col: j),
                                to  : toCellCoord(row: i, col: toC)))
                        }
                    } else {
                        let toR = i + 2
                        if toR < maxRow {
                            setCell(toR, j, cellPath)
                            continuation.yield(.pushed(
                                from: toCellCoord(row: i,   col: j),
                                to  : toCellCoord(row: toR, col: j)))
                        }
                    }
                    moves += 1
                    numWallPushes += 1
                }
                j += 2
            }
        }
        return moves
    }

    // ------------------------------------------------------------------
    // MARK: - Solving  (port of maze.c::solve_maze and friends)
    // ------------------------------------------------------------------

    private mutating func followPath(row: inout Int, col: inout Int) -> Bool {
        var lastHeading = -1
        pathDepth = 0
        setCell(row, col, cellSolved)
        while begRow <= row, row <= endRow {
            let dirs = findDirections(row: row, col: col,
                                      val: cellPath, searching: false)
            guard let step = dirs.first else { break }
            setCell(row + step.dRow / 2, col + step.dCol / 2, cellSolved)
            row += step.dRow
            col += step.dCol
            setCell(row, col, cellSolved)
            pathLen += 1
            let heading = headingForStep(step)
            if lastHeading != heading {
                lastHeading = heading
                turnCount += 1
            }
        }
        return row > endRow
    }

    private mutating func backTrackPath(row: inout Int, col: inout Int) {
        var lastHeading = -1
        pathDepth = 0
        setCell(row, col, cellTried)
        while true {
            let pathDirs = findDirections(row: row, col: col,
                                          val: cellPath, searching: false)
            if !pathDirs.isEmpty { break }
            let solvedDirs = findDirections(row: row, col: col,
                                            val: cellSolved, searching: false)
            guard let step = solvedDirs.first else { break }
            setCell(row + step.dRow / 2, col + step.dCol / 2, cellTried)
            row += step.dRow
            col += step.dCol
            setCell(row, col, cellTried)
            pathLen -= 1
            let heading = headingForStep(step)
            if lastHeading != heading {
                lastHeading = heading
                turnCount -= 1
            }
        }
    }

    private func headingForStep(_ s: GridStep) -> Int {
        if s.dRow > 0 { return 1 }
        if s.dRow < 0 { return 2 }
        if s.dCol > 0 { return 3 }
        return 4
    }

    private mutating func solveMaze(row: inout Int, col: inout Int) {
        pathLen = 0
        turnCount = 0
        grid[begRow - 1][begCol] = cellSolved
        while !followPath(row: &row, col: &col) {
            backTrackPath(row: &row, col: &col)
        }
        grid[endRow + 1][endCol] = cellSolved
        numSolves += 1
    }

    private mutating func restoreSolverMarkers() {
        for r in 0..<maxRow {
            for c in 0..<maxCol {
                if grid[r][c] == cellSolved || grid[r][c] == cellTried {
                    grid[r][c] = cellPath
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // MARK: - Best-opening search  (port of maze.c::search_best_openings)
    // ------------------------------------------------------------------

    private mutating func createOpenings(row: inout Int, col: inout Int) {
        // The `row` and `col` arguments coming into search_best_openings'
        // helper repurpose the variable names: caller passes (start, finish)
        // as (top-col, bottom-col). We mirror that.
        begCol = row     // top column
        endCol = col     // bottom column
        grid[begRow - 1][begCol] = cellPath
        grid[endRow + 1][endCol] = cellPath
        row = begRow
        col = begCol
    }

    private mutating func deleteOpenings() {
        grid[begRow - 1][begCol] = cellWall
        grid[endRow + 1][endCol] = cellWall
    }

    private mutating func searchBestOpenings(row: inout Int, col: inout Int) {
        var bestPathLen = 0
        var bestTurnCnt = 0
        var bestStart   = 2
        var bestFinish  = 2
        for i in 0..<params.width {
            for j in 0..<params.width {
                let start  = 2 * (i + 1)
                let finish = 2 * (j + 1)
                // Skip starts/ends that don't have walls on both sides
                // (those wouldn't be a real opening on the border).
                if grid[begRow][start  - 1] != cellWall, grid[begRow][start  + 1] != cellWall { continue }
                if grid[endRow][finish - 1] != cellWall, grid[endRow][finish + 1] != cellWall { continue }
                var pr = start
                var pc = finish
                createOpenings(row: &pr, col: &pc)
                solveMaze(row: &pr, col: &pc)
                if pathLen > bestPathLen
                  || (pathLen == bestPathLen && turnCount > bestTurnCnt) {
                    bestStart      = start
                    bestFinish     = finish
                    bestTurnCnt    = turnCount
                    bestPathLen    = pathLen
                    maxPathLength  = pathLen
                }
                restoreSolverMarkers()
                deleteOpenings()
            }
        }
        var pr = bestStart
        var pc = bestFinish
        createOpenings(row: &pr, col: &pc)
        // Solve once more so the grid carries the winning solution
        // and we can extract the path for the final Maze.
        solveMaze(row: &pr, col: &pc)
        row = pr
        col = pc
    }

    // ------------------------------------------------------------------
    // MARK: - Solution path extraction
    // ------------------------------------------------------------------

    /// Walk the SOLVED cells from entrance to exit and produce an
    /// ordered list of cell-space Coords.
    private func currentSolutionPath() -> [Coord]? {
        // Walk through SOLVED cells using the standard 4-neighbor adjacency.
        // Start at entrance (just inside the maze).
        var path: [Coord] = []
        var visited = Set<Int>()
        var row = begRow
        var col = begCol
        guard grid[row][col] == cellSolved else { return nil }
        path.append(toCellCoord(row: row, col: col))
        visited.insert(encode(row, col))
        while !(row == endRow && col == endCol) {
            var advanced = false
            for step in cardinalSteps {
                let mr = row + step.dRow / 2
                let mc = col + step.dCol / 2
                let nr = row + step.dRow
                let nc = col + step.dCol
                guard nr > 0, nc > 0, nr < maxRow, nc < maxCol else { continue }
                if grid[mr][mc] == cellSolved, grid[nr][nc] == cellSolved,
                   !visited.contains(encode(nr, nc)) {
                    row = nr; col = nc
                    path.append(toCellCoord(row: row, col: col))
                    visited.insert(encode(row, col))
                    advanced = true
                    break
                }
            }
            if !advanced { break }
        }
        return path
    }
}
