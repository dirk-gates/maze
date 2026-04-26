// GeneratorParameters -- inputs to a Generator run.
//
// Mirrors the maze.c command-line knobs plus a couple of explicit
// safety caps that were implicit in the C version:
//   width, height           -- maze size in cells
//   lookAheadDepth          -- recursive look-ahead depth (0 = off)
//   minPathLength           -- if set, regenerate until solution >= this
//   maxAttempts             -- cap on regen attempts when chasing minPathLength
//   maxLookAheadChecks      -- safety cap on per-call recursion
//   seed                    -- nil = time-based, else deterministic
//                              (when regenerating with minPathLength, the
//                              seed advances by one each attempt so we
//                              don't loop forever on an unsatisfiable seed)

public struct GeneratorParameters: Sendable {
    public var width             : Int
    public var height            : Int
    public var lookAheadDepth    : Int
    public var minPathLength     : Int?
    public var maxAttempts       : Int
    public var maxLookAheadChecks: Int
    public var seed              : UInt64?

    public init(
        width             : Int,
        height            : Int,
        lookAheadDepth    : Int     = 0,
        minPathLength     : Int?    = nil,
        maxAttempts       : Int     = 100,
        maxLookAheadChecks: Int     = 500_000,
        seed              : UInt64? = nil
    ) {
        self.width              = width
        self.height             = height
        self.lookAheadDepth     = lookAheadDepth
        self.minPathLength      = minPathLength
        self.maxAttempts        = maxAttempts
        self.maxLookAheadChecks = maxLookAheadChecks
        self.seed               = seed
    }
}
