// Solver -- maze solver. Skeleton; full algorithm port lands next.
//
// Implementation will mirror maze.c's solve_maze / follow_path /
// back_track_path / search_best_openings: single-threaded depth-first
// search with backtracking, used internally by Generator's
// best-openings pass and externally for "show solution" UX.

public actor Solver {
    public init() {}

    /// Begin solving. Returns a stream of SolveEvents.
    /// Final event is always `.solved(path: [Coord])`.
    public nonisolated func solve(_ maze: Maze) -> AsyncStream<SolveEvent> {
        AsyncStream { continuation in
            Task.detached {
                // TODO(Phase 1): port follow_path + back_track_path.
                // Skeleton emits an empty solved path so the API surface
                // is exercised by tests.
                continuation.yield(.solved(path: []))
                continuation.finish()
            }
        }
    }
}
