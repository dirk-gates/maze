// SmokeTests -- minimum viable tests proving the package compiles
// and the API surface works end-to-end. Real correctness tests
// (parity, properties) land alongside the algorithm port.

import Testing
@testable import MazeKit

@Test("PRNG is deterministic for a given seed")
func prngDeterminism() {
    var a = SplitMix64(seed: 42)
    var b = SplitMix64(seed: 42)
    for _ in 0..<100 {
        #expect(a.next() == b.next())
    }
}

@Test("PRNG produces different streams for different seeds")
func prngDifferentSeeds() {
    var a = SplitMix64(seed: 1)
    var b = SplitMix64(seed: 2)
    var anyDifferent = false
    for _ in 0..<10 {
        if a.next() != b.next() { anyDifferent = true; break }
    }
    #expect(anyDifferent)
}

@Test("nextInt(below:) stays in range")
func prngBound() {
    var rng = SplitMix64(seed: 12345)
    for _ in 0..<1000 {
        let v = rng.nextInt(below: 7)
        #expect(v >= 0 && v < 7)
    }
}

@Test("WallTile bitmask round-trip")
func wallTileBitmask() {
    for n in [false, true] {
        for e in [false, true] {
            for s in [false, true] {
                for w in [false, true] {
                    let tile = WallTile.from(north: n, east: e, south: s, west: w)
                    let mask = (n ? 1 : 0) | (e ? 2 : 0) | (s ? 4 : 0) | (w ? 8 : 0)
                    #expect(tile.rawValue == mask)
                }
            }
        }
    }
}

@Test("Direction step + opposite are consistent")
func directionConsistency() {
    for d in Direction.allCases {
        let s  = d.step
        let os = d.opposite.step
        #expect(s.dx == -os.dx)
        #expect(s.dy == -os.dy)
    }
}

@Test("Generator skeleton produces a finished event")
func generatorSkeleton() async {
    let gen    = Generator(GeneratorParameters(width: 5, height: 3, seed: 1))
    var events: [GenerationEvent] = []
    for await event in gen.generate() {
        events.append(event)
    }
    #expect(!events.isEmpty)
    if case .finished(let maze) = events.last! {
        #expect(maze.width  == 5)
        #expect(maze.height == 3)
    } else {
        Issue.record("last event must be .finished")
    }
}
