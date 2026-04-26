// Generator -- maze generator. Skeleton; full algorithm port lands next.
//
// Lifecycle:
//   1. Create with parameters.
//   2. Call generate() to get an AsyncStream of GenerationEvent.
//   3. Iterate the stream; the final event is .finished(Maze).
//
// Implementation note: actor for thread-safety of stats during long
// generations, but the carving algorithm itself is single-threaded
// (per the project plan -- multi-threaded carving was empirically
// shown not to improve maze quality, and visual "parallel carving" is
// done in the renderer by replaying events in spatial groups).

public actor Generator {
    private let params: GeneratorParameters

    public init(_ params: GeneratorParameters) {
        self.params = params
    }

    /// Begin generation. Returns a stream of GenerationEvents.
    /// The final event is always `.finished(Maze)`. After that the
    /// stream is closed.
    public nonisolated func generate() -> AsyncStream<GenerationEvent> {
        AsyncStream { continuation in
            Task.detached { [params] in
                // TODO(Phase 1): port carve + look-ahead + orphan + push.
                // For now, emit a single empty maze so the package
                // compiles and tests can drive the API surface.
                let entrance = Coord(x: 0,                y: 0)
                let exit     = Coord(x: params.height - 1, y: 0)
                let grid     = [[UInt8]](
                    repeating: [UInt8](repeating: 1, count: 2 * params.width + 3),
                    count    : 2 * params.height + 3
                )
                let maze = Maze(
                    width   : params.width,
                    height  : params.height,
                    entrance: entrance,
                    exit    : exit,
                    grid    : grid
                )
                continuation.yield(.finished(maze))
                continuation.finish()
            }
        }
    }
}
