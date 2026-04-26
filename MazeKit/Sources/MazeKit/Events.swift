// Events -- async-stream event types emitted by Generator and Solver.
//
// Renderers subscribe to the AsyncStream returned by generate() / solve()
// and use the events to animate. Engine emits events in the order they
// happen; the renderer can group, batch, or replay as desired (e.g. the
// "fake parallelism" animation groups events by spatial region and emits
// them concurrently to the Canvas).

public enum GenerationEvent: Sendable {
    /// A new attempt has begun. Emitted at the start of every attempt
    /// when a Generator with `minPathLength` is regenerating because
    /// the previous attempt didn't meet the threshold. Renderers that
    /// want to clear and re-animate can hook this; renderers that just
    /// want the final result can ignore it.
    case attempt(Int)

    /// A cell was carved (wall -> path).
    case carved(Coord)

    /// The look-ahead probed this cell at the given recursion depth.
    /// Renderer can flash it briefly to visualize WHY the maze is hard.
    case considering(Coord, depth: Int)

    /// Mid-wall-opening push moved a passage from `from` to `to`.
    case pushed(from: Coord, to: Coord)

    /// Top and bottom edge gates have been chosen and opened.
    case opened(entrance: Coord, exit: Coord)

    /// Generation complete. Final immutable maze attached.
    case finished(Maze)
}

public enum SolveEvent: Sendable {
    /// Cell visited as part of the current candidate path.
    case visited(Coord)

    /// Cell backtracked away from (dead end).
    case backtracked(Coord)

    /// Solving complete. Full path from entrance to exit attached.
    case solved(path: [Coord])
}
