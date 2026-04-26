// Events -- async-stream event types emitted by Generator and Solver.
//
// Renderers subscribe to the AsyncStream returned by generate() / solve()
// and use the events to animate. Engine emits events in the order they
// happen; the renderer can group, batch, or replay as desired.
//
// The full set of events together is enough to render the maze
// state-by-state without ever asking the engine for a snapshot:
//
//     starting state:    everything is wall (paint white)
//     .carved(c)          a cell became path
//     .opened(edge)       a wall between two cells was removed
//     .closed(edge)       a wall was re-added (only fires during the
//                         mid-wall-opening push pass)
//     .gates(...)         entrance/exit gaps appear in the border
//     .finished(maze)     final maze attached
//
// .considering and .pushed are advisory -- renderers can ignore them.

public enum GenerationEvent: Sendable {
    /// A new attempt has begun. Emitted at the start of every attempt
    /// when a Generator with `minPathLength` is regenerating.
    case attempt(Int)

    /// A cell was carved (wall -> path).
    case carved(Coord)

    /// A wall between two adjacent cells was removed (path now exists
    /// between them).
    case opened(Edge)

    /// A wall between two adjacent cells was added back (the only place
    /// this fires today is during the mid-wall-opening push, which
    /// closes one slot and opens another adjacent one).
    case closed(Edge)

    /// The look-ahead probed this cell at the given recursion depth.
    /// Renderer can flash it briefly to visualize WHY the maze is hard.
    case considering(Coord, depth: Int)

    /// Mid-wall-opening push moved a passage from `from` to `to`.
    /// (`closed` and `opened` events are also emitted around this; the
    /// `.pushed` event is a higher-level summary.)
    case pushed(from: Coord, to: Coord)

    /// Top and bottom edge gates have been chosen and opened.
    case gates(entrance: Coord, exit: Coord)

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
