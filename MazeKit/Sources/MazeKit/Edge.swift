// Edge -- an unordered pair of adjacent cell Coords. Used to identify
// a wall slot between two cells regardless of which side initiated
// the connection. Hashable so renderers can keep a Set<Edge> of
// currently-open walls.

public struct Edge: Hashable, Sendable {
    public let a: Coord
    public let b: Coord

    public init(_ p: Coord, _ q: Coord) {
        // Canonical ordering: smaller (y, x) first so Edge(p, q) == Edge(q, p).
        if (p.y, p.x) <= (q.y, q.x) {
            self.a = p
            self.b = q
        } else {
            self.a = q
            self.b = p
        }
    }
}
