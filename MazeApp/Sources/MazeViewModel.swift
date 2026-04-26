// MazeViewModel -- observable state container. Owns the Generator and
// Solver tasks and translates their event streams into UI-friendly
// state (a set of carved cells during generation, a partial solution
// path during solving, etc.).

import Foundation
import MazeKit
import Observation

@MainActor
@Observable
final class MazeViewModel {
    // ----- configuration (Settings will mutate these later) -----
    var width         : Int     = 30
    var height        : Int     = 20
    var lookAheadDepth: Int     = 0
    var seed          : UInt64? = nil
    var animationSpeed: Double  = 0.65   // 0 = slow, 1 = instant

    // ----- runtime state observed by the views -----
    var maze         : Maze?      = nil
    var carvedCells  : Set<Coord> = []
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

        var carved = 0
        for await event in stream {
            if Task.isCancelled { break }
            await delayPerCell()

            switch event {
            case .attempt(let n):
                attemptCount = n
                carved = 0
                carvedCells.removeAll()
                statsLine = "attempt \(n)…"
            case .carved(let c):
                carvedCells.insert(c)
                carved += 1
                statsLine = "\(carved) cells carved"
            case .considering, .pushed, .opened:
                break
            case .finished(let m):
                maze      = m
                statsLine = "\(carved) cells, "
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
            try? await Task.sleep(nanoseconds: 30_000_000)   // 30ms / cell
            switch event {
            case .visited(let c):
                solutionPath.append(c)
                solveProgress = solutionPath.count
            case .solved(let path):
                solutionPath = path
                solveProgress = path.count
            case .backtracked:
                break
            }
        }
    }

    private func delayPerCell() async {
        // animationSpeed 0 = slowest (50ms per cell)
        // animationSpeed 1 = instant (no delay)
        let ms = (1.0 - animationSpeed) * 50.0
        if ms < 0.5 { return }
        try? await Task.sleep(nanoseconds: UInt64(ms * 1_000_000))
    }
}
