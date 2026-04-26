# maze

Simple maze generator and solver, implemented three times.

| File       | Language | Notes                                                                       |
|------------|----------|-----------------------------------------------------------------------------|
| `maze.c`   | C        | Original Linux/macOS version, POSIX termios. Single-threaded.              |
| `maze.cpp` | C++      | Windows port (`<windows.h>` console). Single-threaded.                     |
| `maze.go`  | Go       | Multi-threaded generation **and** solving. Atomic-op clean. Most complete. |

## Build

```bash
# C (Linux / macOS)
cc -O2 -o maze maze.c -lm

# C++ (Windows; MSVC or MinGW)
cl maze.cpp                       # MSVC
g++ -O2 -o maze.exe maze.cpp      # MinGW

# Go
go build -o maze maze.go
```

## Run

The Go version has the most flags; the others are a subset.

```bash
./maze -w 80 -h 30 -t 8 -look 4 -fps 60 -view -solve
```

| Flag        | Meaning                                                              |
|-------------|----------------------------------------------------------------------|
| `-w` / `-h` | Width / height of the maze (cells). Defaults to terminal-fit.        |
| `-t`        | Worker threads for generation and solving (Go only).                 |
| `-look`     | Recursive look-ahead depth. Higher = fewer dead ends, more CPU.      |
| `-fps`      | Animation frame rate when `-view` or `-solve` is set.                |
| `-view`     | Animate generation in real time.                                     |
| `-solve`    | Animate solving in real time and render the solution path.           |
| `-seed`     | Fixed seed for reproducible mazes (otherwise time-based).            |

Run `./maze -h` (or `--help`) for the full flag list of any version.

## Algorithm

Carves paths through a fully-walled grid via random walk, with a few
twists:

1. **Path seeding** -- new paths start only at the corners of existing
   paths, which biases the result toward longer corridors and fewer
   one-cell branches.
2. **Look-ahead** -- before committing a move, recursively check that
   it won't strand a 1x1 orphan cell. Depth is configurable.
3. **Wall pushing** -- after generation, mid-wall openings are slid
   left and down to give the maze a consistent visual flow.
4. **Gate selection** -- the solver picks the top-row entry and
   bottom-row exit that produce the longest solution path.
5. **Solving** -- depth-first with backtracking. In Go this runs
   across multiple worker threads coordinating via atomic operations
   on the maze grid.

## Multi-threading (Go)

`maze.go` parallelizes both generation and solving. All cell accesses
go through `sync/atomic` and read-modify-write sequences use
`CompareAndSwap`. Run with `-race` during development:

```bash
go run -race maze.go -t 8 -solve
```

## Status

This is a personal project that's been ported and re-ported as a way
to learn each language; the C version dates to 2016, Go to 2020, and
both will keep evolving.

## License

Copyright (c) 2016-2026 Dirk Gates. All rights reserved.
