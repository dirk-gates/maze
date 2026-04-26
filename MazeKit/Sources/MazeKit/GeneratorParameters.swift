// GeneratorParameters -- inputs to a Generator run.
//
// Mirrors the maze.c command-line knobs:
//   width, height           -- maze size in cells
//   lookAheadDepth          -- recursive look-ahead depth (0 = off)
//   minPathLength           -- if set, regenerate until solution >= this
//   maxLookAheadChecks      -- safety cap on per-call recursion
//   seed                    -- nil = time-based, else deterministic

public struct GeneratorParameters: Sendable {
    public var width             : Int
    public var height            : Int
    public var lookAheadDepth    : Int
    public var minPathLength     : Int?
    public var maxLookAheadChecks: Int
    public var seed              : UInt64?

    public init(
        width             : Int,
        height            : Int,
        lookAheadDepth    : Int     = 0,
        minPathLength     : Int?    = nil,
        maxLookAheadChecks: Int     = 500_000,
        seed              : UInt64? = nil
    ) {
        self.width              = width
        self.height             = height
        self.lookAheadDepth     = lookAheadDepth
        self.minPathLength      = minPathLength
        self.maxLookAheadChecks = maxLookAheadChecks
        self.seed               = seed
    }
}
