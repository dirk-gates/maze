// DailyMaze -- a "maze of the day". Derives a stable seed from the
// device-local calendar date, plus fixed dims + look-ahead so every
// device that opens the daily on the same date generates the same
// maze. Lets us add a featured "Today's Daily" row in the library
// without storing anything new -- the seed is the date.
//
// Local date (not UTC) follows the Wordle convention: each user
// has their own "today" in their own timezone, which matches the
// intuitive sense of the word more than a strict UTC midnight cut.

import Foundation

public enum DailyMaze {
    /// Fixed dimensions for the daily maze. Same across all
    /// devices so the puzzle is shareable / discussable.
    public static let width         : Int = 30
    public static let height        : Int = 40
    public static let lookAheadDepth: Int = 5

    /// Derive the daily seed for `date`. Default is `Date()`.
    /// Stable for the entire local-calendar day -- changes at the
    /// user's local midnight.
    public static func seed(for date: Date = Date(),
                            calendar: Calendar = .current) -> UInt64
    {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = UInt64(comps.year  ?? 2026)
        let m = UInt64(comps.month ?? 1)
        let d = UInt64(comps.day   ?? 1)
        let key = y &* 10_000 &+ m &* 100 &+ d   // e.g. 20260426
        // SplitMix64 finalizer mixing key bits into a well-
        // distributed 64-bit seed.
        var x = key
        x = (x ^ (x >> 30)) &* 0xbf58476d1ce4e5b9
        x = (x ^ (x >> 27)) &* 0x94d049bb133111eb
        x =  x ^ (x >> 31)
        return x
    }

    /// Human-readable identifier for today's daily, e.g. "2026-04-26".
    /// Useful for labels and share text.
    public static func dateKey(for date: Date = Date(),
                               calendar: Calendar = .current) -> String
    {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                      comps.year  ?? 2026,
                      comps.month ?? 1,
                      comps.day   ?? 1)
    }
}
