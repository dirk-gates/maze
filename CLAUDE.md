# CLAUDE.md - maze

Simple maze generator and solver, implemented three times (C, C++, Go).
Recursive look-ahead path generation, push-mid-wall openings, multi-
threaded generation and solving (Go only). ASCII/terminal output.

## Philosophy

This codebase will outlive you. Every shortcut becomes someone else's
burden. Fight entropy. Leave the codebase better than you found it.

## Plan Mode

- Make the plan extremely concise. Sacrifice grammar for the sake of concision.
- At the end of each plan, give me a list of unresolved questions to answer, if any.
- Save plan files to the harness's plan directory (not in the repo).

## Permissions

- Allow web search (WebSearch tool) for any query
- Allow URL fetching (WebFetch tool) for any URL
- Allow all web-related operations without restriction

## Project Overview

| File       | Language | Status / Notes                                                                       |
|------------|----------|--------------------------------------------------------------------------------------|
| `maze.c`   | C        | Original (Linux / macOS, POSIX termios). Single-threaded. Rev 1.6.                  |
| `maze.cpp` | C++      | Windows port (uses `<windows.h>` for console I/O). Single-threaded.                  |
| `maze.go`  | Go       | Most-advanced version. Multi-threaded generation **and** solving. Atomic-op clean. Rev 2.3. |

The three are functionally equivalent on the algorithm side; differences
are in platform glue (terminal/console handling) and concurrency model.

## Algorithm summary

| Phase      | What                                                                                          |
|------------|-----------------------------------------------------------------------------------------------|
| Generate   | Random walk path-carving, only starting new paths at corners of existing paths.               |
| Look ahead | Recursive variable-depth check that a candidate move doesn't strand a 1x1 orphan.             |
| Polish     | Push mid-wall openings left and down so the maze prefers a particular visual flow.            |
| Pick gates | Solve to find the longest top-row entry / bottom-row exit pair.                               |
| Solve      | Find a path from entry to exit (multi-threaded in Go).                                        |

## Build & Run

```bash
# C (Linux/macOS)
cc -O2 -o maze maze.c -lm
./maze --help

# C++ (Windows; needs MSVC or MinGW)
cl maze.cpp                  # MSVC
g++ -O2 -o maze.exe maze.cpp # MinGW

# Go
go build -o maze maze.go
./maze --help

# Common runtime flags (Go version, most complete):
./maze -w 80 -h 30 -t 8 -look 4 -fps 60 -view -solve
#   -w/-h    width/height of the maze
#   -t       worker threads for generation/solving
#   -look    look-ahead depth (recursion)
#   -fps     animation frame rate
#   -view    show generation in real time
#   -solve   show solving in real time
```

Run with `-race` on Go during development to catch unsynchronized access:

```bash
go run -race maze.go -t 8 -solve
```

## File Organization

| Artifact                | Location                            |
|-------------------------|-------------------------------------|
| Source                  | repo root (`maze.c`, `maze.cpp`, `maze.go`) |
| Build output            | repo root (`maze`, `a.out`, `maze.exe`) -- gitignored |
| Plan files              | harness plan directory, **not** in the repo |

## Git Commit Style

### Subject Line

- ~50 characters (soft limit)
- Module prefix lowercase + colon: `module: Description`
- Capitalize first word after module identifier
- No period at end
- Imperative mood ("Fix race" not "Fixed race")
- Test: "If applied, this commit will [subject line]"

### Module Identifiers

| Prefix    | Scope                                  |
|-----------|----------------------------------------|
| `c:`      | `maze.c`                               |
| `cpp:`    | `maze.cpp`                             |
| `go:`     | `maze.go`                              |
| `docs:`   | `README.md`, `CLAUDE.md`               |
| (none)    | cross-cutting changes (e.g. an algorithm change ported across all three) |

### Body

- Separate from subject with a blank line
- Wrap at 72 characters
- Explain **what** changed and **why**, not **how**

## Code Formatting - Column Alignment

All **new and modified** code should be column-aligned wherever possible.
Align constants, declarations, conditionals, struct/array literals,
function parameters, and trailing comments. Forward-looking only -- don't
reformat existing code that you aren't otherwise touching.

This codebase already follows the convention heavily; preserve it.

**Constants** -- align names, `=`, values, and trailing comments:

```go
const (
    blank        = ' '  // ' '
    block        = 0x61 // '#'
    rightBottom  = 0x6a // '+'
    rightTop     = 0x6b // '+'
    intersection = 0x6e // '+'
)
```

**Variable declarations** -- align names and types:

```go
maxX, maxY        int32
begX, endX        int32
begY, endY        int32
depth             int32
delay             int32
solvedFlag        int32
```

**Tabular literals** -- pad each column so commas line up:

```go
stdDirection = [4]dirTable { { 2,  0, down },
                             {-2,  0, up   },
                             { 0,  2, right},
                             { 0, -2, left } }
```

**Inline comments** -- start at the same column within a block:

```c
maze[x][y] = WALL;       // outer border
maze[x][1] = PATH;       // entry gap
maze[x][2] = TRIED;      // marker for solver
```

**Markdown** -- use tables for any list of terms / key-value content.

## Multi-threading Notes (Go)

`maze.go` is multi-threaded. Treat all shared state with care:

| Concern              | Guideline                                                                                          |
|----------------------|----------------------------------------------------------------------------------------------------|
| Maze cells           | All reads/writes go through `atomic.LoadInt32` / `atomic.StoreInt32` / `atomic.CompareAndSwapInt32`. |
| Stat counters        | `numPaths`, `numSolves`, `pathLen`, `turnCnt`, etc. are `int32`; mutate with `atomic.AddInt32`.      |
| Display channel      | The display goroutine consumes `displayChan` -- don't write to it from inside critical sections.    |
| Re-entrancy          | Look-ahead is recursive. State passed in, not stashed in globals.                                   |
| `-race`              | Run dev builds with `-race`. Any new shared variable that fails it must be made atomic before merge. |

If you need a non-atomic global, prove (in the commit message) that it's
written exactly once at startup and never again.

## Code Preferences

| Preference                          | Detail                                                                                              |
|-------------------------------------|-----------------------------------------------------------------------------------------------------|
| **Match existing patterns**         | The three implementations share variable names and algorithm structure; new feature -> port the same way to all three or commit (none) cross-cutting. |
| **Avoid over-engineered error handling** | This is a CLI tool. Bail with a useful message; don't try to recover from internal invariant violations. |
| **Minimum allocations**             | Maze grid is a fixed-size array; keep it that way. No dynamic resize during generation/solving.     |
| **Pure where possible**             | Generation should be deterministic given a seed. Don't introduce wall-clock dependencies in the algorithm itself. |

## Behavioral Guidelines

| #  | Guideline                  | Detail                                                                                                                                            |
|----|----------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------|
| 1  | **Think Before Coding**    | Don't assume; surface tradeoffs. State assumptions. If multiple interpretations exist, present them. If unclear, stop and ask.                    |
| 2  | **Simplicity First**       | Minimum code that solves the problem. Nothing speculative. No abstractions for single-use code. If 200 lines could be 50, rewrite.                |
| 3  | **Surgical Changes**       | Touch only what you must. Don't "improve" adjacent code. Match existing style. Every changed line should trace to the user's request.             |
| 4  | **Verify End-to-End**      | After any algorithmic change: build, run with `-view -solve` on a small grid (20x10), and a stress run with multiple threads + `-race` (Go only). |
| 5  | **Describe Before Diving** | For any concurrency change in `maze.go`, describe the approach and wait for approval. Race conditions are easy to introduce, hard to diagnose.    |
| 6  | **Break Down Large Changes** | If more than 1 of the 3 implementations changes, stop and break into smaller per-language tasks first.                                          |
| 7  | **Continuous Improvement** | Every time the user corrects you, add a rule here so it never happens again.                                                                      |

## Engineering Lessons

### Port After Proving, Not Before

When extending the algorithm (look-ahead, new flag, new heuristic), get
it working in **one** implementation first -- usually `maze.go` since
it's the most complete. Validate with `-race`, with multiple threads, and
with edge-case grid sizes. **Then** port back to `maze.c` / `maze.cpp`.
Porting an unproven design across three languages multiplies debugging
cost by three.

### One Behavior Across Three Languages

Cross-cutting changes (algorithm, flag semantics, output format) should
land in all three implementations, ideally in one commit per language
with a `(none)` cross-cutting summary commit. Drift between them is the
biggest long-term maintenance risk.

### Look-Ahead Depth Has Quadratic Cost

The recursive look-ahead is `O(branches^depth)`. Tuning past `-look 6`
on a multi-thousand-cell maze becomes the dominant cost. If introducing
a new heuristic, measure look-ahead depth + worker thread interaction
before declaring success.

### Atomic Doesn't Mean Synchronized

Each individual cell write is atomic, but a sequence of "read cell ->
decide -> write cell" is not. Use `CompareAndSwap` for read-modify-write
on the maze grid, not separate load/store pairs. The current code does
this correctly; new code should too.
