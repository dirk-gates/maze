// MazeViewModel -- observable state container. Owns the Generator and
// Solver tasks and translates their event streams into UI-friendly
// state for the Canvas-based renderer.

import Foundation
import MazeKit
import Observation

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
    var seed          : UInt64? = nil
    var animationSpeed: Double  = 0.65   // 0 = slow, 1 = instant
    var appearance    : AppearancePreference = .system

    // ----- runtime state observed by the views -----
    var maze         : Maze?      = nil
    var carvedCells  : Set<Coord> = []
    var openWalls    : Set<Edge>  = []
    var entranceGate : Coord?     = nil
    var exitGate     : Coord?     = nil
    var solutionPath : [Coord]    = []
    var solveProgress: Int        = 0
    var attemptCount : Int        = 0
    var isGenerating : Bool       = false
    var isSolving    : Bool       = false
    var statsLine    : String     = ""

    // ----- private -----
    private var task: Task<Void, Never>?

    // ----- intents -----

    func generate() {
        cancel()
        task = Task { [weak self] in await self?.runGenerate() }
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

    private func runGenerate() async {
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
        let stream = Generator(params).generate()

        for await event in stream {
            if Task.isCancelled { break }
            await delayPerCell()

            switch event {
            case .attempt(let n):
                attemptCount = n
                carvedCells.removeAll()
                openWalls.removeAll()
                entranceGate = nil
                exitGate     = nil
                statsLine = "attempt \(n)…"
            case .carved(let c):
                carvedCells.insert(c)
                statsLine = "\(carvedCells.count) cells carved"
                Haptics.shared.carveTick()
            case .opened(let edge):
                openWalls.insert(edge)
            case .closed(let edge):
                openWalls.remove(edge)
            case .gates(let entrance, let exit):
                entranceGate = entrance
                exitGate     = exit
                Haptics.shared.milestone()
            case .considering, .pushed:
                break
            case .finished(let m):
                maze      = m
                statsLine = "\(carvedCells.count) cells, "
                          + "solution \(m.solution?.count ?? 0)"
            }
        }
    }

    private func runSolve() async {
        guard let maze else { return }
        solutionPath.removeAll()
        solveProgress = 0
        isSolving = true
        defer { isSolving = false }

        for await event in Solver().solve(maze) {
            if Task.isCancelled { break }
            await delayPerCell()
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

    private func delayPerCell() async {
        // Logarithmic / constant-ratio response. Each equal-sized
        // slider movement produces the same RELATIVE speed change
        // (~3x faster per 25% of travel), so the perceived rate of
        // change feels uniform across the whole slider range. The
        // earlier polynomial curves clustered "near-instant" values
        // into the top 20% of slider, so small thumb movements there
        // jumped between very different visual feels.
        //
        // The very top 2% of slider is treated as instant (no delay)
        // so users who just want to skip the animation can pin the
        // slider to the right.
        if animationSpeed >= 0.98 { return }
        let maxMs = 50.0
        let minMs = 0.5
        let ms = maxMs * pow(minMs / maxMs, animationSpeed)
        try? await Task.sleep(nanoseconds: UInt64(ms * 1_000_000))
    }
}
