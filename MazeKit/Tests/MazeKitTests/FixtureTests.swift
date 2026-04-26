// FixtureTests -- "self-fixture" lock-in.
//
// On first run, generates each named fixture and writes its rendered
// ASCII to Tests/MazeKitTests/Fixtures/<name>.txt. The test passes
// with an Issue note saying "review and commit."
//
// On every subsequent run, the same generation is compared against
// the committed file. Any algorithm change -- intentional bug fix,
// PRNG behavior tweak, look-ahead refactor, anything -- that alters
// the output for a known seed will trip a fixture test, forcing the
// developer to consciously decide whether the change is correct and
// regenerate the fixture (delete the file, re-run the test).
//
// Locking these fixtures down means we can refactor freely later
// without silently changing the mazes users have come to recognize
// (e.g. saved seeds in the eventual .maze file format).

import Testing
import Foundation
@testable import MazeKit

@Suite("Fixture lock-in")
struct FixtureTests {

    /// Test source file -> Fixtures/ directory next to it.
    static let fixturesDir: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
    }()

    /// (name, width, height, seed, lookAhead) tuples covering the
    /// algorithm's main code paths:
    ///   - tiny: simplest possible maze
    ///   - small: small enough to read at a glance
    ///   - medium: realistic phone-sized maze
    ///   - lookahead: exercises the recursive look-ahead heuristic
    static let cases: [FixtureCase] = [
        FixtureCase(name: "tiny",      width:  5, height: 3, seed: 1,  lookAhead: 0),
        FixtureCase(name: "small",     width:  8, height: 5, seed: 7,  lookAhead: 0),
        FixtureCase(name: "medium",    width: 12, height: 8, seed: 42, lookAhead: 0),
        FixtureCase(name: "lookahead", width: 10, height: 6, seed: 3,  lookAhead: 3),
    ]

    @Test("Fixture parity", arguments: cases)
    func fixtureParity(_ c: FixtureCase) async throws {
        let p = GeneratorParameters(
            width         : c.width,
            height        : c.height,
            lookAheadDepth: c.lookAhead,
            seed          : c.seed
        )
        var final: Maze?
        for await event in Generator(p).generate() {
            if case .finished(let m) = event { final = m }
        }
        guard let maze = final else {
            Issue.record("\(c.name): no .finished event")
            return
        }
        let actual = maze.asciiRender()
        let url    = Self.fixturesDir.appendingPathComponent("\(c.name).txt")

        if FileManager.default.fileExists(atPath: url.path) {
            let expected = try String(contentsOf: url, encoding: .utf8)
            #expect(actual == expected, """
                Fixture '\(c.name)' drifted.

                Expected:
                \(expected)
                Actual:
                \(actual)
                If this is intentional, delete the fixture file and
                re-run the test to regenerate.
                """)
        } else {
            try FileManager.default.createDirectory(
                at                          : Self.fixturesDir,
                withIntermediateDirectories : true
            )
            try actual.write(to: url, atomically: true, encoding: .utf8)
            Issue.record("Created new fixture \(c.name).txt at \(url.path) -- review and commit.")
        }
    }
}

struct FixtureCase: Sendable, CustomStringConvertible {
    let name     : String
    let width    : Int
    let height   : Int
    let seed     : UInt64
    let lookAhead: Int

    var description: String {
        "\(name)(\(width)x\(height) seed=\(seed) look=\(lookAhead))"
    }
}
