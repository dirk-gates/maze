// SavedMaze -- persistent record of a generated maze. Holds the seed
// + parameters needed to deterministically regenerate (SplitMix64 +
// look-ahead are stable across runs / platforms), plus metadata
// (when it was generated, optional user-supplied name).
//
// Lives in MazeKit so the library schema is platform-agnostic and
// can be shared via iCloud or share-sheet payloads later.

import Foundation

public struct SavedMaze: Codable, Identifiable, Sendable, Hashable {
    public let id            : UUID
    public var name          : String?
    public let seed          : UInt64
    public let width         : Int
    public let height        : Int
    public let lookAheadDepth: Int
    public let createdAt     : Date

    public init(
        id            : UUID    = UUID(),
        name          : String? = nil,
        seed          : UInt64,
        width         : Int,
        height        : Int,
        lookAheadDepth: Int,
        createdAt     : Date    = Date()
    ) {
        self.id             = id
        self.name           = name
        self.seed           = seed
        self.width          = width
        self.height         = height
        self.lookAheadDepth = lookAheadDepth
        self.createdAt      = createdAt
    }
}
