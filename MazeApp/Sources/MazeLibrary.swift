// MazeLibrary -- on-disk history of generated mazes. JSON file in
// the app's Documents directory, auto-loaded on init and rewritten
// whenever the collection changes. Capped FIFO so a long session
// doesn't grow unbounded; pinned/favorited mazes will get exempt
// treatment in a later slice.

import Foundation
import MazeKit
import Observation

@MainActor
@Observable
final class MazeLibrary {
    private(set) var mazes: [SavedMaze] = []

    /// Cap on the persisted history. Beyond this, the oldest entries
    /// get evicted. 200 is plenty for casual play and tiny on disk.
    private let maxEntries = 200

    init() { load() }

    /// Insert at the head, dedupe by (seed, dims, look-ahead) so
    /// re-rolling the same maze doesn't pile duplicates, then prune
    /// to maxEntries and persist. Evicted entries' thumbnails are
    /// deleted from disk to keep the cache tidy.
    func append(_ maze: SavedMaze) {
        let dupes = mazes.filter {
               $0.seed           == maze.seed
            && $0.width          == maze.width
            && $0.height         == maze.height
            && $0.lookAheadDepth == maze.lookAheadDepth
        }
        for d in dupes {
            if let f = d.thumbnailFilename { MazeThumbnail.delete(filename: f) }
        }
        mazes.removeAll { d in dupes.contains { $0.id == d.id } }
        mazes.insert(maze, at: 0)
        if mazes.count > maxEntries {
            for evicted in mazes.suffix(mazes.count - maxEntries) {
                if let f = evicted.thumbnailFilename {
                    MazeThumbnail.delete(filename: f)
                }
            }
            mazes.removeLast(mazes.count - maxEntries)
        }
        save()
    }

    func remove(at offsets: IndexSet) {
        for i in offsets {
            if let f = mazes[i].thumbnailFilename {
                MazeThumbnail.delete(filename: f)
            }
        }
        mazes.remove(atOffsets: offsets)
        save()
    }

    func remove(_ maze: SavedMaze) {
        if let f = maze.thumbnailFilename {
            MazeThumbnail.delete(filename: f)
        }
        mazes.removeAll { $0.id == maze.id }
        save()
    }

    func clear() {
        for m in mazes {
            if let f = m.thumbnailFilename {
                MazeThumbnail.delete(filename: f)
            }
        }
        mazes.removeAll()
        save()
    }

    // ----- private I/O -----

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory,
                                           in : .userDomainMask).first!
        return dir.appendingPathComponent("MazeLibrary.json")
    }

    private func load() {
        guard let data    = try? Data(contentsOf: MazeLibrary.fileURL),
              let decoded = try? JSONDecoder().decode([SavedMaze].self, from: data)
        else { return }
        mazes = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(mazes) else { return }
        try? data.write(to: MazeLibrary.fileURL, options: .atomic)
    }
}
