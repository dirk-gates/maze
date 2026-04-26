// MazeViewModel -- observable state container. Owns the Generator and
// Solver tasks and translates their event streams into UI-friendly
// state for the Canvas-based renderer.

import Foundation
import MazeKit
import Observation
import SwiftUI

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
        // Slider response: log curve over a deliberately tight range
        // (60ms .. 3ms), with the top 10% of travel mapped to instant.
        // Earlier curves stretched all the way to 0.5ms, which is
        // below the perceptual / display-refresh floor -- the upper
        // chunk of the slider felt "twitchy" because tiny thumb
        // movements moved between values the eye can't distinguish.
        // 60→3ms is ~20x dynamic range and stays visible end-to-end;
        // the wide instant zone gives users a clear "skip animation"
        // park spot at the right edge.
        let instantThreshold = 0.90
        if animationSpeed >= instantThreshold { return }
        let t     = animationSpeed / instantThreshold
        let maxMs = 60.0
        let minMs = 3.0
        let ms    = maxMs * pow(minMs / maxMs, t)
        try? await Task.sleep(nanoseconds: UInt64(ms * 1_000_000))
    }
}
