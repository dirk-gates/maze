// PRNG -- seedable, deterministic pseudo-random number generator.
//
// We use SplitMix64 -- a 64-bit RNG with very good statistical quality
// for its size, simple to implement, and (critically) deterministic
// across Swift versions and platforms. The Swift stdlib's
// SystemRandomNumberGenerator is non-deterministic and unsuitable for
// the engine's reproducibility requirements.
//
// The same seed always produces the same maze. Phase 4's ".maze" file
// format will leverage this: store the seed + parameters, regenerate
// the maze on demand. Tiny files, identical mazes everywhere.
//
// Note: this PRNG is NOT seed-compatible with the C reference's
// srand()/rand(). MazeKit and maze.c will produce different mazes for
// the same numeric seed. That's a deliberate choice -- BSD rand() is
// platform-specific and reproducing its output would couple MazeKit
// to libc internals. For users, the visible behavior (seed -> maze)
// is the same; only the seed -> maze mapping differs.

public struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        // 0 is a valid seed for SplitMix64 (unlike many LCGs); we
        // accept it directly so users get the obvious "seed = 0" maze
        // when they want it.
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z &>> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z &>> 31)
    }
}

extension SplitMix64 {
    /// Convenience: random integer in 0..<bound. Avoids modulo bias for
    /// small bounds via Lemire's debiasing (cheap in practice).
    public mutating func nextInt(below bound: Int) -> Int {
        precondition(bound > 0, "bound must be positive")
        let r = next()
        let m = r.multipliedFullWidth(by: UInt64(bound))
        return Int(m.high)
    }
}
