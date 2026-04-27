// MazeViewModel -- observable state container. Owns the Generator and
// Solver tasks and translates their event streams into UI-friendly
// state for the Canvas-based renderer.

import CoreGraphics
import Foundation
import MazeKit
import Observation
import SwiftUI

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .system: return "System"
        case .light : return "Light"
        case .dark  : return "Dark"
        }
    }
}

@MainActor
@Observable
final class MazeViewModel {
    // ----- configuration (Settings will mutate these later) -----
    var width         : Int     = 30
    var height        : Int     = 20
    var lookAheadDepth: Int     = 0
    var animationSpeed: Double  = 0.65   // 0 = slow, 1 = instant
    var appearance    : AppearancePreference = .system

    /// Seed actually used by the most recent / current generation.
    /// Captured so we can persist it to the library and replay later.
    /// Always concrete (never nil) -- if the user hasn't pinned a
    /// seed via load(_:), generate() picks a fresh random one.
    private(set) var currentSeed: UInt64 = 0

    /// Persistent history of generated mazes. Auto-appended to on
    /// every successful .finished event.
    let library: MazeLibrary

    /// Translates the user's appearance preference into the value
    /// expected by `.preferredColorScheme(_:)`. `.system` becomes
    /// `nil`, which releases any prior override and lets SwiftUI
    /// fall back to the OS-level setting. Applied at WindowGroup
    /// scope so it reaches sheets too.
    var schemeOverride: ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light : return .light
        case .dark  : return .dark
        }
    }

    // ----- runtime state observed by the views -----
    var maze         : Maze?      = nil
    var carvedCells  : Set<Coord> = []
    var openWalls    : Set<MazeKit.Edge>  = []
    var entranceGate : Coord?     = nil
    var exitGate     : Coord?     = nil
    var solutionPath : [Coord]    = []
    var solveProgress: Int        = 0
    var attemptCount : Int        = 0
    var isGenerating : Bool       = false
    var isSolving    : Bool       = false
    var statsLine    : String     = ""

    // Latest known maze canvas size + target unit pixels, set by
    // ContentView via a GeometryReader. We refit width/height to
    // these whenever a new generation is kicked off, but NOT on
    // arbitrary geometry changes (e.g. orientation flips) -- those
    // leave the existing maze and dims alone.
    var canvasSize  : CGSize  = .zero
    var targetUnitPx: CGFloat = 8

    // ----- private -----
    private var task: Task<Void, Never>?
    /// Pinned seed for the *next* generation only. Set by load(_:);
    /// consumed by generate() and reset to nil so subsequent
    /// Generate taps roll a fresh random seed.
    private var pinnedSeed: UInt64? = nil

    // ----- init -----

    init(library: MazeLibrary = MazeLibrary()) {
        self.library = library
    }

    // ----- intents -----

    func generate() {
        fitDimensionsToCanvas()
        let seed = pinnedSeed ?? UInt64.random(in: UInt64.min ... UInt64.max)
        pinnedSeed   = nil
        currentSeed  = seed
        cancel()
        task = Task { [weak self] in await self?.runGenerate(usingSeed: seed) }
    }

    /// Replay a previously-saved maze. Restores its parameters and
    /// generates with the same seed so the resulting maze is byte-
    /// identical to the original.
    func load(_ saved: SavedMaze) {
        width          = saved.width
        height         = saved.height
        lookAheadDepth = saved.lookAheadDepth
        pinnedSeed     = saved.seed
        generate()
    }

    /// Generate today's "daily maze" -- fixed dims and look-ahead
    /// across all devices, with a seed derived from the device-
    /// local calendar date. Same date → same maze, everywhere.
    func loadDaily(for date: Date = Date()) {
        width          = DailyMaze.width
        height         = DailyMaze.height
        lookAheadDepth = DailyMaze.lookAheadDepth
        pinnedSeed     = DailyMaze.seed(for: date)
        generate()
    }

    /// Zoom in (smaller targetUnitPx → cells get smaller, more of them
    /// fit) or out (larger targetUnitPx → bigger cells, fewer of them).
    /// The maze is always refit-and-regenerated so it keeps filling
    /// the canvas. Clamped to a sane range so zoom can't push the cell
    /// size below 3px (illegible) or above 32px (silly chunky).
    func zoom(by factor: CGFloat) {
        let next = (targetUnitPx * factor).clamped(to: 3 ... 32)
        guard next != targetUnitPx else { return }
        targetUnitPx = next
        generate()
    }

    /// Recompute width/height so the maze fills `canvasSize` at the
    /// current `targetUnitPx`. Called only when launching a new
    /// generation -- never on incidental layout passes.
    private func fitDimensionsToCanvas() {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        // Maze grid in "units": w cells take 4w+1 units (3 per cell + 1 wall, with one extra wall).
        let w = max(4, Int((canvasSize.width  / targetUnitPx - 1) / 4))
        let h = max(4, Int((canvasSize.height / targetUnitPx - 1) / 4))
        width  = w
        height = h
    }

    func solve() {
        cancel()
        task = Task { [weak self] in await self?.runSolve() }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isGenerating = false
        isSolving    = false
    }

    // ----- private runners -----

    private func runGenerate(usingSeed seed: UInt64) async {
        carvedCells.removeAll()
        openWalls.removeAll()
        entranceGate = nil
        exitGate     = nil
        solutionPath.removeAll()
        solveProgress = 0
        attemptCount  = 0
        maze          = nil
        isGenerating  = true
        defer { isGenerating = false }

        let params = GeneratorParameters(
            width         : width,
            height        : height,
            lookAheadDepth: lookAheadDepth,
            seed          : seed
        )
        let stream     = Generator(params).generate()
        let totalCells = max(1, width * height)

        // Pacing is re-derived from `animationSpeed` on every flush
        // so live slider tweaks (drag, +/- buttons, turtle/hare
        // taps) take effect immediately instead of being locked in
        // at run-start. Pegging the slider mid-run drops into the
        // instant fast path until .finished arrives.

        var pendingCells : [Coord]         = []
        var pendingOpens : [MazeKit.Edge]  = []
        var pendingCloses: [MazeKit.Edge]  = []

        @MainActor func flushPending() {
            if !pendingCells.isEmpty {
                for c in pendingCells { carvedCells.insert(c) }
                statsLine = "\(carvedCells.count) cells carved"
                pendingCells.removeAll(keepingCapacity: true)
            }
            for e in pendingOpens  { openWalls.insert(e) }
            for e in pendingCloses { openWalls.remove(e) }
            pendingOpens.removeAll (keepingCapacity: true)
            pendingCloses.removeAll(keepingCapacity: true)
        }

        for await event in stream {
            if Task.isCancelled { break }

            // Live slider read -- pegged means "skip remaining
            // animation, just wait for the finished maze".
            let speed = animationSpeed
            if speed >= instantThreshold {
                switch event {
                case .attempt(let n):
                    attemptCount = n
                case .finished(let m):
                    pendingCells.removeAll(keepingCapacity: true)
                    pendingOpens.removeAll(keepingCapacity: true)
                    pendingCloses.removeAll(keepingCapacity: true)
                    populateRenderState(from: m)
                    maze      = m
                    statsLine = "\(carvedCells.count) cells, "
                              + "solution \(m.solution?.count ?? 0)"
                    appendToLibrary(m, seed: seed)
                default:
                    break
                }
                continue
            }

            switch event {
            case .attempt(let n):
                flushPending()
                attemptCount = n
                carvedCells.removeAll()
                openWalls.removeAll()
                entranceGate = nil
                exitGate     = nil
                statsLine = "attempt \(n)…"
            case .carved(let c):
                pendingCells.append(c)
                let (cellsPerFrame, frameDelayMs) =
                    pacing(speed: speed, totalCells: totalCells)
                if pendingCells.count >= cellsPerFrame {
                    flushPending()
                    Haptics.shared.carveTick()
                    await sleepMs(frameDelayMs)
                }
            case .opened(let edge):
                pendingOpens.append(edge)
            case .closed(let edge):
                pendingCloses.append(edge)
            case .gates(let entrance, let exit):
                flushPending()
                entranceGate = entrance
                exitGate     = exit
                Haptics.shared.milestone()
            case .considering, .pushed:
                break
            case .finished(let m):
                flushPending()
                maze      = m
                statsLine = "\(carvedCells.count) cells, "
                          + "solution \(m.solution?.count ?? 0)"
                appendToLibrary(m, seed: seed)
            }
        }
    }

    /// Convert (slider position, total cell count) into a (cells-
    /// per-flush, frame-delay-ms) pair. Caps at 60fps -- if the
    /// slider would imply > 60 frames per second, we instead show
    /// more cells per frame at a fixed 60fps cadence. If it would
    /// imply < 60fps, frames slow down to match.
    private func pacing(speed: Double, totalCells: Int)
        -> (cellsPerFrame: Int, frameDelayMs: Double)
    {
        let targetSecs = targetTotalSecs(slider: speed)
        // Just-below-instant: still show frames, no per-frame sleep.
        if targetSecs < 0.05 {
            return (max(1, totalCells / 60), 0)
        }
        let cellsPerSec   = Double(totalCells) / targetSecs
        let cellsPerFrame = max(1, Int(ceil(cellsPerSec / 60.0)))
        let frameDelayMs  = Double(cellsPerFrame) * 1000.0 / cellsPerSec
        return (cellsPerFrame, frameDelayMs)
    }

    /// Map the slider position to a target TOTAL animation time
    /// (seconds, excluding compute). Tiered curve: pegged-down is
    /// ~60s; one click below pegged-up is a few seconds. Power
    /// 0.7 spreads the short times across the top of the slider so
    /// one tap of the rabbit/turtle = a noticeable change up there.
    private func targetTotalSecs(slider: Double) -> Double {
        let normalized = max(0, min(1, (instantThreshold - slider) / instantThreshold))
        let maxSecs    = 60.0
        return maxSecs * pow(normalized, 0.7)
    }

    private func sleepMs(_ ms: Double) async {
        if ms <= 0 { return }
        try? await Task.sleep(nanoseconds: UInt64(ms * 1_000_000))
    }

    /// Fill carvedCells, openWalls, entranceGate, exitGate from a
    /// finished maze in one batch. Used by the instant-mode fast
    /// path so we trigger a single render pass instead of one per
    /// carved cell.
    private func populateRenderState(from m: Maze) {
        var cells = Set<Coord>()
        var walls = Set<MazeKit.Edge>()
        cells.reserveCapacity(m.width * m.height)
        for y in 0..<m.height {
            for x in 0..<m.width {
                let here = Coord(x: x, y: y)
                cells.insert(here)
                if x + 1 < m.width {
                    let east = Coord(x: x + 1, y: y)
                    if !m.wall(between: here, east) {
                        walls.insert(MazeKit.Edge(here, east))
                    }
                }
                if y + 1 < m.height {
                    let south = Coord(x: x, y: y + 1)
                    if !m.wall(between: here, south) {
                        walls.insert(MazeKit.Edge(here, south))
                    }
                }
            }
        }
        carvedCells  = cells
        openWalls    = walls
        entranceGate = m.entrance
        exitGate     = m.exit
    }

    private func appendToLibrary(_ m: Maze, seed: UInt64) {
        let id    = UUID()
        let thumb = MazeThumbnail.write(maze: m, id: id)
        library.append(SavedMaze(
            id               : id,
            seed             : seed,
            width            : width,
            height           : height,
            lookAheadDepth   : lookAheadDepth,
            thumbnailFilename: thumb
        ))
    }

    private func runSolve() async {
        guard let maze else { return }
        solutionPath.removeAll()
        solveProgress = 0
        isSolving = true
        defer { isSolving = false }

        for await event in Solver().solve(maze) {
            if Task.isCancelled { break }
            await solveDelay()
            switch event {
            case .visited(let c):
                solutionPath.append(c)
                solveProgress = solutionPath.count
            case .solved(let path):
                solutionPath = path
                solveProgress = path.count
                Haptics.shared.success()
            case .backtracked:
                break
            }
        }
    }

    /// Slider position at and above which we treat generation as
    /// "skip animation" -- no per-cell delay AND we collapse the
    /// per-event UI churn into one batch update at .finished. Set
    /// to 0.99 so only a pegged-right slider triggers instant;
    /// anything below stays animated (rabbit-tap from 0.975 lands
    /// cleanly on 1.0 with the 0.025 step).
    fileprivate let instantThreshold = 0.99

    /// Per-step delay in the SOLVE animation. Solve is so cheap
    /// (one cell per event, no compute heft) that the old log curve
    /// is fine here -- only generation needs the batched-frame
    /// pacing scheme.
    private func solveDelay() async {
        if animationSpeed >= instantThreshold { return }
        let t     = animationSpeed / instantThreshold
        let maxMs = 80.0
        let minMs = 1.0
        let ms    = maxMs * pow(minMs / maxMs, t)
        try? await Task.sleep(nanoseconds: UInt64(ms * 1_000_000))
    }
}
