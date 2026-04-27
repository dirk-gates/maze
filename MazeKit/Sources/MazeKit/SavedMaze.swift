// SavedMaze -- persistent record of a generated maze. Holds the seed
// + parameters needed to deterministically regenerate (SplitMix64 +
// look-ahead are stable across runs / platforms), plus metadata
// (when it was generated, optional user-supplied name).
//
// Lives in MazeKit so the library schema is platform-agnostic and
// can be shared via iCloud or share-sheet payloads later.

import Foundation

/// Parameters extracted from a share URL. Enough to recreate the
/// maze byte-for-byte via the generator.
public struct SharedMazeParameters: Sendable {
    public let seed          : UInt64
    public let width         : Int
    public let height        : Int
    public let lookAheadDepth: Int
    public let name          : String?
}

public struct SavedMaze: Codable, Identifiable, Sendable, Hashable {
    public let id               : UUID
    public var name             : String?
    public let seed             : UInt64
    public let width            : Int
    public let height           : Int
    public let lookAheadDepth   : Int
    public let createdAt        : Date
    /// Filename (no path) of a cached PNG thumbnail in the app's
    /// Documents/thumbnails directory. Optional so library files
    /// written before thumbnails existed still decode.
    public var thumbnailFilename: String?

    public init(
        id               : UUID    = UUID(),
        name             : String? = nil,
        seed             : UInt64,
        width            : Int,
        height           : Int,
        lookAheadDepth   : Int,
        createdAt        : Date    = Date(),
        thumbnailFilename: String? = nil
    ) {
        self.id                = id
        self.name              = name
        self.seed              = seed
        self.width             = width
        self.height            = height
        self.lookAheadDepth    = lookAheadDepth
        self.createdAt         = createdAt
        self.thumbnailFilename = thumbnailFilename
    }

    // ----- share URLs -----

    /// A `maze://load?...` URL that, when opened on a device with
    /// the app installed, regenerates this maze byte-for-byte. Seed
    /// is base-36 to keep the URL shorter than decimal.
    public func shareURL() -> URL {
        var c = URLComponents()
        c.scheme = "maze"
        c.host   = "load"
        var items: [URLQueryItem] = [
            URLQueryItem(name: "s", value: String(seed, radix: 36)),
            URLQueryItem(name: "w", value: String(width)),
            URLQueryItem(name: "h", value: String(height)),
            URLQueryItem(name: "l", value: String(lookAheadDepth)),
        ]
        if let name, !name.isEmpty {
            items.append(URLQueryItem(name: "n", value: name))
        }
        c.queryItems = items
        return c.url!
    }

    /// Parse a share URL back into its parameters, or nil if it
    /// isn't a recognizable maze:// load URL.
    public static func parse(url: URL) -> SharedMazeParameters? {
        guard url.scheme == "maze",
              url.host   == "load",
              let comps  = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items  = comps.queryItems
        else { return nil }
        var dict: [String: String] = [:]
        for item in items where item.value != nil {
            dict[item.name] = item.value
        }
        guard let seedStr = dict["s"],
              let seed    = UInt64(seedStr, radix: 36),
              let wStr    = dict["w"], let w = Int(wStr),
              let hStr    = dict["h"], let h = Int(hStr),
              let lStr    = dict["l"], let l = Int(lStr)
        else { return nil }
        return SharedMazeParameters(seed          : seed,
                                    width         : w,
                                    height        : h,
                                    lookAheadDepth: l,
                                    name          : dict["n"])
    }
}
