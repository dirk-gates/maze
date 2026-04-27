// MazeLibrary -- on-disk history of generated mazes plus iCloud
// key-value sync. JSON file in Documents (truth on this device);
// the same JSON also lives in NSUbiquitousKeyValueStore so other
// devices on the same iCloud account converge.
//
// Conflict policy: union by SavedMaze.id on every change. Any
// device adding an entry propagates to all others. Deletes don't
// propagate (no tombstones in v1) -- a personal-use trade-off
// that keeps additions safe at the cost of having to delete on
// each device individually if you really want it gone everywhere.
//
// Thumbnails are NOT synced -- they'd blow the 1 MB KV limit.
// Library rows for cloud-arrived entries with a filename but no
// local file fall back to the placeholder cell (regenerating
// would mean replaying the algorithm).

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

    private static let kvKey  = "MazeApp.library.v1"
    private let kvStore       = NSUbiquitousKeyValueStore.default
    private var kvObserver    : NSObjectProtocol?

    init() {
        load()
        // Subscribe to remote changes BEFORE the initial pull so we
        // don't miss anything that lands during init.
        kvObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object : kvStore,
            queue  : .main
        ) { [weak self] _ in
            // The notification itself isn't Sendable, but we don't
            // need any payload from it -- just hop to the MainActor
            // and pull current KV store state.
            Task { @MainActor [weak self] in
                self?.applyKVStore()
            }
        }
        // Kick the initial sync. synchronize() schedules an upload /
        // download as needed and is non-blocking.
        kvStore.synchronize()
        applyKVStore()
    }

    // No deinit cleanup -- this library lives the whole app lifetime
    // and the observer closure captures self weakly, so a stray late
    // notification just no-ops.

    /// Insert at the head, dedupe by (seed, dims, look-ahead) so
    /// re-rolling the same maze doesn't pile duplicates, then prune
    /// to maxEntries and persist + sync. Evicted entries' thumbnails
    /// are deleted from local disk to keep the cache tidy.
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
        persist()
    }

    func remove(at offsets: IndexSet) {
        for i in offsets {
            if let f = mazes[i].thumbnailFilename {
                MazeThumbnail.delete(filename: f)
            }
        }
        mazes.remove(atOffsets: offsets)
        persist()
    }

    func remove(_ maze: SavedMaze) {
        if let f = maze.thumbnailFilename {
            MazeThumbnail.delete(filename: f)
        }
        mazes.removeAll { $0.id == maze.id }
        persist()
    }

    func clear() {
        for m in mazes {
            if let f = m.thumbnailFilename {
                MazeThumbnail.delete(filename: f)
            }
        }
        mazes.removeAll()
        persist()
    }

    // ----- private I/O -----

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory,
                                           in : .userDomainMask).first!
        return dir.appendingPathComponent("MazeLibrary.json")
    }

    /// Load local-file state into `mazes`. Best-effort -- a missing
    /// or corrupt file just leaves the library empty.
    private func load() {
        guard let data    = try? Data(contentsOf: MazeLibrary.fileURL),
              let decoded = try? JSONDecoder().decode([SavedMaze].self, from: data)
        else { return }
        mazes = decoded
    }

    /// Write `mazes` to the local file AND push to iCloud KV. Any
    /// other devices on the same iCloud account will receive a
    /// `didChangeExternallyNotification` and merge.
    private func persist() {
        guard let data = try? JSONEncoder().encode(mazes) else { return }
        try? data.write(to: MazeLibrary.fileURL, options: .atomic)
        // KV writes are silently capped at 1 MB total; library at
        // 200 entries × ~150 bytes ≈ 30 KB so we're well under.
        kvStore.set(data, forKey: MazeLibrary.kvKey)
        kvStore.synchronize()
    }

    /// Pull whatever is currently in the KV store and union-merge it
    /// with our local state. Called on init and from the change
    /// notification. If the merge produced something different from
    /// what's in KV, we push the merged result back so peers catch
    /// up to whatever new entries WE had.
    private func applyKVStore() {
        guard let data     = kvStore.data(forKey: MazeLibrary.kvKey),
              let incoming = try? JSONDecoder().decode([SavedMaze].self, from: data)
        else { return }
        let merged = mergeUnion(local: mazes, incoming: incoming)
        if merged != mazes {
            mazes = merged
            // Save the merged result locally regardless. Only push
            // back to KV if our merge added entries the cloud didn't
            // have -- avoids a feedback loop on plain cloud→local.
            if let mergedData = try? JSONEncoder().encode(mazes) {
                try? mergedData.write(to: MazeLibrary.fileURL, options: .atomic)
            }
            if merged != incoming {
                if let mergedData = try? JSONEncoder().encode(mazes) {
                    kvStore.set(mergedData, forKey: MazeLibrary.kvKey)
                    kvStore.synchronize()
                }
            }
        }
    }

    /// Union by SavedMaze.id. Incoming wins on id collision (so a
    /// rename / metadata update from another device propagates).
    /// Sort newest-first and cap at maxEntries so devices converge
    /// to the same trimmed list.
    private func mergeUnion(local: [SavedMaze], incoming: [SavedMaze]) -> [SavedMaze] {
        var byID: [UUID: SavedMaze] = [:]
        for m in local    { byID[m.id] = m }
        for m in incoming { byID[m.id] = m }
        let sorted = byID.values.sorted { $0.createdAt > $1.createdAt }
        return Array(sorted.prefix(maxEntries))
    }
}
