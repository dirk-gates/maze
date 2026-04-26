// CellKind -- the three states a maze grid cell can be in for engine
// purposes. Solver-time states (.tried, .check, .solved) do not appear
// in the public Maze data model -- that surfaces only the post-solve
// .path/.wall final state plus an optional solution path. Solver-time
// states are produced as events and consumed by the renderer for
// animation, then discarded.

public enum CellKind: Sendable, Equatable {
    case path
    case wall
}
