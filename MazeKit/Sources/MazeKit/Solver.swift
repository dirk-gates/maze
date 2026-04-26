// Solver -- streams a re-solve of an already-generated maze for
// animation purposes. The Maze object already carries its `.solution`
// (computed during best-opening search inside Generator), so most
// callers won't need this -- it exists for the "show me the solver
// thinking" UX where the user wants to watch the depth-first walk.

public actor Solver {
    public init() {}

    public nonisolated func solve(_ maze: Maze) -> AsyncStream<SolveEvent> {
        AsyncStream { continuation in
            Task.detached(priority: .userInitiated) {
                if let path = maze.solution {
                    // Walk the known path one cell at a time.
                    for c in path {
                        continuation.yield(.visited(c))
                    }
                    continuation.yield(.solved(path: path))
                } else {
                    // No solution available -- emit empty.
                    continuation.yield(.solved(path: []))
                }
                continuation.finish()
            }
        }
    }
}
