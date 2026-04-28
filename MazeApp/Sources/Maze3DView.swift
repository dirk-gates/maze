// Maze3DView -- RealityKit-backed 3D rendering of a finished Maze.
// Phase 5b: first-person camera at eye height with iOS twin-stick
// controls (left = move, right = look) and axis-separated wall
// collision. Reaching the exit cell flashes a "you escaped"
// overlay. macOS keeps an overhead camera until WASD/mouselook
// lands in a follow-up slice.
//
// World coordinates:
//   +X right, +Y up, +Z forward (into the screen, away from the
//   maze entrance which sits at z=0).
//   maze grid x → world x; maze grid y → world z. One cell =
//   `cellSize` world units; walls `wallThickness` thick by
//   `wallHeight` tall. Floor at y=0; player eye at `eyeHeight`.

import CoreMotion
import MazeKit
import RealityKit
import SwiftUI

// MARK: - World constants

private let cellSize     : Float = 1.0
private let wallThickness: Float = 0.18
private let eyeHeight    : Float = 1.55
// `wallHeight` is no longer a file-level constant -- it comes
// from viewModel.hedgeHeight.meters so users can drop the hedges
// to waist height to see across the maze. Values that need it
// outside Maze3DView's struct (PlayerState's flyClearance) get
// it via init parameter.

// MARK: - Collision

/// Axis-aligned wall rectangle in the maze's XZ plane.
private struct WallAABB {
    let minX: Float, maxX: Float
    let minZ: Float, maxZ: Float
}

// MARK: - Player

/// Live first-person state. Bound to RealityView's per-frame
/// scene update so movement / look input applied this frame
/// shows up next frame. Inputs are SIMD2<Float> in -1...1 set
/// by the joystick gestures.
@MainActor
@Observable
private final class PlayerState {
    var position : SIMD3<Float>     // .y already includes altitudeOffset
    var yaw      : Float
    var pitch    : Float = 0
    var won      : Bool         = false

    /// Target world (X, Z) for the in-progress cell-by-cell step.
    /// nil = stationary. Replaced by the next step() call -- so
    /// the player can chain quick taps and the camera will follow
    /// each new target as it's set.
    var stepTarget: SIMD2<Float>?

    /// Current camera height ABOVE eye-height. 0 = walking on the
    /// floor; positive = hovering. The camera Y is always
    /// `eyeHeight + altitudeOffset`.
    var altitudeOffset: Float = 0
    /// Lerp target for `altitudeOffset`; tick() interpolates the
    /// current value toward it so altitude changes feel smooth.
    var targetAltitude: Float = 0

    /// True when we're high enough to be over the top of the
    /// hedges -- collision is disabled in this state so the player
    /// can fly across the maze without being walled in.
    var isFlying: Bool { altitudeOffset > flyClearance }

    let maxAltitude  : Float
    /// "We're above the hedges" threshold. Set from the wall
    /// height in this session (waist vs tall) so flying-over
    /// kicks in at the right altitude for the chosen hedge size.
    private let flyClearance: Float

    private let walls       : [WallAABB]
    private let width       : Int
    private let height      : Int
    private let maze        : Maze   // for BFS pathfinding when tap-to-walking
    private let exitCellX   : Int
    private let exitCellZ   : Int
    private let playerRadius: Float = 0.22
    private let stepSpeed   : Float = 3.5   // cells per second during a step lerp
    private let altitudeRate: Float = 4.0   // 1/seconds: ~0.25 s to converge

    /// Cells queued by walkTo(_:). Each completed step lerp pulls
    /// the next cell off the queue and starts a new step. Single
    /// D-pad taps clear this queue; tap-to-walk replaces it.
    private var pathQueue: [Coord] = []

    // ----- VR look (CoreMotion) -----
    /// True while the device-motion stream is driving yaw + pitch.
    /// Drag-to-look becomes a no-op while this is on.
    var vrEnabled: Bool = false
    /// Captured device attitude at the moment VR mode is turned
    /// on. Subsequent samples are expressed relative to this so
    /// the view stays put when the phone is held still and
    /// rotates only when the phone rotates.
    private var vrRefAttitude: CMAttitude?
    /// Player yaw / pitch at the moment VR mode is turned on --
    /// motion deltas are added on top, not replacing.
    private var vrBaseYaw  : Float = 0
    private var vrBasePitch: Float = 0

    init(start: SIMD3<Float>, yaw: Float,
         walls: [WallAABB],
         maze : Maze,
         exitCellX: Int, exitCellZ: Int,
         maxAltitude: Float,
         wallHeight: Float)
    {
        self.position     = start
        self.yaw          = yaw
        self.walls        = walls
        self.width        = maze.width
        self.height       = maze.height
        self.maze         = maze
        self.exitCellX    = exitCellX
        self.exitCellZ    = exitCellZ
        self.maxAltitude  = maxAltitude
        // Clamp to a sensible minimum: with waist-high hedges
        // (0.95 m) and eye at 1.55 m, the bare formula goes
        // negative, which makes `isFlying` true at ground level
        // and disables horizontal movement. The clamp keeps the
        // walking → flying transition at ~0.3 m of altitude in
        // every hedge mode.
        self.flyClearance = max(0.3, wallHeight - eyeHeight + 0.1)
    }

    func applyLookDelta(_ delta: CGSize) {
        // VR mode owns yaw/pitch -- swallow drag input so the
        // gyro doesn't fight it.
        guard !vrEnabled else { return }
        let sens: Float = 0.005
        yaw   -= Float(delta.width)  * sens
        pitch -= Float(delta.height) * sens
        pitch = max(-1.4, min(1.4, pitch))
    }

    /// Switch on VR look. Captures the player's current yaw +
    /// pitch as the baseline and clears the reference attitude
    /// (the next motion sample becomes the zero-orientation).
    func startVR() {
        vrEnabled    = true
        vrBaseYaw    = yaw
        vrBasePitch  = pitch
        vrRefAttitude = nil
    }

    func stopVR() {
        vrEnabled    = false
        vrRefAttitude = nil
    }

    /// Apply one CoreMotion sample to the player's view. The
    /// device attitude is multiplied by the inverse of the
    /// reference attitude so we get rotation relative to "the
    /// pose the phone was in when VR was enabled". Yaw goes to
    /// camera yaw; pitch goes to camera pitch (clamped).
    func applyMotion(_ motion: CMDeviceMotion) {
        guard vrEnabled else { return }
        let attitude = motion.attitude.copy() as! CMAttitude
        if vrRefAttitude == nil {
            vrRefAttitude = attitude
            return
        }
        if let ref = vrRefAttitude {
            attitude.multiply(byInverseOf: ref)
        }
        // CoreMotion uses East-up-North-ish frames depending on
        // settings; for a portrait-held phone the yaw axis is
        // vertical (rotating phone left/right around its long
        // axis... wait no, that's roll). For portrait the most
        // natural mapping is:
        //   user turns body left  → phone yaws CCW (negative)
        //                         → camera should yaw CCW (negative)
        //   user tips phone down  → phone pitches negative
        //                         → camera pitch negative (look down)
        // The rotation around the camera's local X (camera pitch)
        // matches the device's "roll" when phone is portrait,
        // since the device's pitch axis runs across the screen
        // horizontally. Swap pitch ← attitude.roll.
        let dyaw   = Float(attitude.yaw)
        let dpitch = Float(attitude.roll)
        yaw   = vrBaseYaw   + dyaw
        pitch = max(-1.4, min(1.4, vrBasePitch + dpitch))
    }

    /// Step exactly one cell relative to the player's facing.
    /// `forward` and `strafe` are -1, 0, or 1. Yaw is snapped to
    /// the nearest cardinal direction so movement always lands on
    /// a clean grid cell, regardless of how the camera is rotated.
    /// Blocked moves (walls in the way) silently no-op.
    ///
    /// If a previous step's lerp is still in progress, we snap to
    /// the in-flight target FIRST so the new step is a clean
    /// cell-center-to-cell-center jump regardless of how fast the
    /// user taps. A queued tap-to-walk path is also cancelled --
    /// manual D-pad input always wins.
    func step(forward: Int, strafe: Int) {
        guard !won else { return }
        guard !isFlying else { return }

        // Cancel any auto-walk path -- this is a manual one-cell
        // step.
        pathQueue.removeAll()

        // Snap to the in-flight target if we're mid-lerp -- guarantees
        // every step starts from a cell center.
        if let target = stepTarget {
            position.x = target.x
            position.z = target.y
            stepTarget = nil
        }

        // Snap yaw to nearest cardinal multiple of π/2.
        let snapped = round(yaw / (.pi / 2)) * (.pi / 2)
        // Forward / right vectors in cardinal-grid space.
        let fx = Float(-sin(snapped))
        let fz = Float(-cos(snapped))
        // Right of "facing snapped" is forward rotated -90° around Y.
        // (cos(s)*fx + ... etc -- but cardinal snap makes this trivial.)
        let rx = -fz
        let rz =  fx
        let dx = fx * Float(forward) + rx * Float(strafe)
        let dz = fz * Float(forward) + rz * Float(strafe)

        // Current cell in maze coords.
        let cx = Int(floor(position.x / cellSize))
        let cz = Int(floor(position.z / cellSize))
        // Nearest integer for direction (rounds the trig values).
        let stepX = Int(round(dx))
        let stepZ = Int(round(dz))
        let targetX = cx + stepX
        let targetZ = cz + stepZ

        // Block walking off the maze grid.
        guard targetX >= 0, targetX < width,
              targetZ >= 0, targetZ < height
        else { return }

        // Check the midpoint between current and target cell
        // centers -- if a wall AABB intersects the player radius
        // there, the wall slot between cells is closed.
        let midX = (Float(cx) + 0.5 + Float(stepX) * 0.5) * cellSize
        let midZ = (Float(cz) + 0.5 + Float(stepZ) * 0.5) * cellSize
        if collides(at: SIMD3(midX, eyeHeight, midZ)) { return }

        // Commit the step -- lerp will pull position toward the
        // target cell's center each tick.
        let targetWX = (Float(targetX) + 0.5) * cellSize
        let targetWZ = (Float(targetZ) + 0.5) * cellSize
        stepTarget = SIMD2(targetWX, targetWZ)
    }

    /// Step the altitude target up / down. Caller usually calls
    /// these from button taps; the actual altitude lerps toward
    /// the target across multiple ticks.
    func raiseAltitude(by step: Float) {
        targetAltitude = min(maxAltitude, targetAltitude + step)
    }
    func lowerAltitude(by step: Float) {
        targetAltitude = max(0, targetAltitude - step)
    }

    /// Apply one frame of altitude lerp + step-target lerp.
    func tick(dt: Float) {
        guard !won else { return }

        // Smooth altitude lerp toward the target the buttons set.
        let beforeFlying = isFlying
        let dy = targetAltitude - altitudeOffset
        altitudeOffset += dy * min(1, dt * altitudeRate)

        var p = position

        // Step-target lerp: pull (x, z) toward the most recent
        // step destination, if any. Each lerp lands on a cell
        // center. When it finishes, advance the auto-walk queue
        // so chained tap-to-walk steps flow into each other.
        if !isFlying, let target = stepTarget {
            let dx = target.x - p.x
            let dz = target.y - p.z
            let dist = sqrt(dx * dx + dz * dz)
            let stepDist = stepSpeed * cellSize * dt
            if dist <= stepDist || dist < 0.001 {
                p.x = target.x
                p.z = target.y
                stepTarget = nil
                // Mutating self while we're using `var p = position`
                // is fine -- we'll commit p at the end of tick().
                // Pull the next path cell off the queue (if any)
                // so auto-walk continues.
                advanceQueue()
            } else {
                let scale = stepDist / dist
                p.x += dx * scale
                p.z += dz * scale
            }
        }
        p.y = eyeHeight + altitudeOffset

        // Landing: if we just dropped below fly clearance and our
        // XZ position is inside a wall, snap to the center of the
        // current cell so collision doesn't trap us.
        if beforeFlying && !isFlying {
            let test = SIMD3(p.x, eyeHeight, p.z)
            if collides(at: test) {
                let cx = (floor(p.x / cellSize) + 0.5) * cellSize
                let cz = (floor(p.z / cellSize) + 0.5) * cellSize
                p.x = cx
                p.z = cz
                stepTarget = nil
            }
        }
        position = p

        // Win condition: stand on the exit cell while NOT flying.
        if !isFlying {
            let cx = Int(position.x / cellSize)
            let cz = Int(position.z / cellSize)
            if cx == exitCellX && cz == exitCellZ {
                won = true
            }
        }
    }

    /// Cell the player is currently in (or about to land in if
    /// a step lerp is in flight). Used by walkTo and the live
    /// solution-path overlay.
    var currentCell: Coord {
        if let target = stepTarget {
            return Coord(
                x: Int(floor(target.x / cellSize)),
                y: Int(floor(target.y / cellSize))
            )
        }
        return Coord(
            x: Int(floor(position.x / cellSize)),
            y: Int(floor(position.z / cellSize))
        )
    }

    /// Path from the player's current cell to the exit, via BFS
    /// through the maze's open corridors. Used by the Solve
    /// toggle in the walk view to show "from where you are".
    func solutionFromHere() -> [Coord] {
        let exit = Coord(x: exitCellX, y: exitCellZ)
        return bfs(from: currentCell, to: exit)
    }

    /// Walk to `target`, navigating along the maze's open
    /// corridors via BFS. The path is queued on `pathQueue` and
    /// each completed step lerp pulls the next cell off
    /// automatically (see tick()). Cancelled by any subsequent
    /// step() (D-pad) call.
    func walkTo(_ target: Coord) {
        guard !won else { return }
        guard !isFlying else { return }

        // Snap to the in-flight target so we BFS from a clean
        // cell center.
        if let stp = stepTarget {
            position.x = stp.x
            position.z = stp.y
            stepTarget = nil
        }

        let cx = Int(floor(position.x / cellSize))
        let cz = Int(floor(position.z / cellSize))
        let here = Coord(x: cx, y: cz)
        guard target != here else {
            pathQueue.removeAll()
            return
        }
        guard target.x >= 0, target.x < width,
              target.y >= 0, target.y < height
        else { return }

        let path = bfs(from: here, to: target)
        // BFS returns the full list including the start; we want
        // only the steps from "next cell" onward.
        pathQueue = Array(path.dropFirst())
        advanceQueue()
    }

    /// Pull the next cell off `pathQueue` and start the lerp.
    private func advanceQueue() {
        guard !pathQueue.isEmpty else { return }
        let next = pathQueue.removeFirst()
        let tx = (Float(next.x) + 0.5) * cellSize
        let tz = (Float(next.y) + 0.5) * cellSize
        stepTarget = SIMD2(tx, tz)
    }

    /// Standard BFS through the maze graph. Edges = cell pairs
    /// with no wall between. Returns [] if no path (shouldn't
    /// happen in a connected maze), otherwise a list starting
    /// with `start` and ending with `goal`.
    private func bfs(from start: Coord, to goal: Coord) -> [Coord] {
        if start == goal { return [start] }
        var visited: Set<Coord> = [start]
        var parent : [Coord: Coord] = [:]
        var queue  : [Coord] = [start]
        var head   = 0
        while head < queue.count {
            let here = queue[head]
            head += 1
            if here == goal {
                var path: [Coord] = [goal]
                var cur = goal
                while let p = parent[cur] {
                    path.insert(p, at: 0)
                    cur = p
                }
                return path
            }
            let neighbours = [
                Coord(x: here.x + 1, y: here.y),
                Coord(x: here.x - 1, y: here.y),
                Coord(x: here.x,     y: here.y + 1),
                Coord(x: here.x,     y: here.y - 1),
            ]
            for n in neighbours {
                guard n.x >= 0, n.x < maze.width,
                      n.y >= 0, n.y < maze.height
                else { continue }
                if visited.contains(n) { continue }
                if maze.wall(between: here, n) { continue }
                visited.insert(n)
                parent[n] = here
                queue.append(n)
            }
        }
        return []
    }

    private func collides(at p: SIMD3<Float>) -> Bool {
        let r = playerRadius
        for w in walls {
            let cx = max(w.minX, min(p.x, w.maxX))
            let cz = max(w.minZ, min(p.z, w.maxZ))
            let dx = p.x - cx
            let dz = p.z - cz
            if dx * dx + dz * dz < r * r { return true }
        }
        return false
    }
}

// MARK: - D-pad

/// 4-way directional pad. Each button calls `onStep` with a
/// (forward, strafe) tuple where each component is -1, 0, or 1.
/// Up = forward 1; down = -1; right = strafe 1; left = -1.
private struct DPad: View {
    let onStep: (_ forward: Int, _ strafe: Int) -> Void

    var body: some View {
        VStack(spacing: 6) {
            button("arrow.up") { onStep( 1,  0) }
            HStack(spacing: 6) {
                button("arrow.left")  { onStep( 0, -1) }
                Color.clear.frame(width: 52, height: 52)
                button("arrow.right") { onStep( 0,  1) }
            }
            button("arrow.down") { onStep(-1,  0) }
        }
    }

    private func button(_ name: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.title2.weight(.semibold))
                .frame(width: 52, height: 52)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.35),
                                         lineWidth: 1))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Virtual joystick (unused -- kept for reference)

/// Floating thumbpad. Drag inside (or anywhere over) it; the
/// knob clamps to the radius and writes a normalized -1...1
/// vector to `value`. Releasing recenters.
private struct VirtualJoystick: View {
    @Binding var value: SIMD2<Float>
    let radius: CGFloat
    let label: String

    @GestureState private var drag: CGSize = .zero

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().stroke(.white.opacity(0.35),
                                         lineWidth: 1))
                .frame(width: radius * 2, height: radius * 2)
            Circle()
                .fill(.white.opacity(0.65))
                .frame(width: radius * 0.7, height: radius * 0.7)
                .offset(x: CGFloat(value.x) * radius,
                        y: CGFloat(-value.y) * radius)   // visual: up = forward
                .allowsHitTesting(false)
        }
        .accessibilityLabel(label)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($drag) { v, state, _ in state = v.translation }
                .onChanged { v in
                    let dx = v.translation.width
                    let dy = v.translation.height
                    let mag = sqrt(dx * dx + dy * dy)
                    let scale = min(mag, radius) / max(radius, 1)
                    if mag > 0 {
                        value = SIMD2(
                            Float(dx / mag) * Float(scale),
                            Float(-dy / mag) * Float(scale)
                        )
                    } else {
                        value = .zero
                    }
                }
                .onEnded { _ in value = .zero }
        )
    }
}

// MARK: - Main view

struct Maze3DView: View {
    let maze: Maze
    /// World-space hedge height for this walk session, in metres.
    /// Comes from viewModel.hedgeHeight.meters so the user can
    /// switch between tall (can't see over) and waist-high (can
    /// see across the maze) in Settings.
    let wallHeight: Float
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    // Built once on view appear.
    @State private var player: PlayerState?
    @State private var walls : [WallAABB] = []
    @State private var cameraEntity   = PerspectiveCamera()
    @State private var solutionEntity = Entity()
    @State private var showingSolution = false

    /// Cinematic-entry flag. While true, the camera is animating
    /// from a high overhead opening shot down to the player's
    /// eye-height starting position; per-frame camera updates and
    /// look / step input are paused so the move(to:) animation
    /// owns the camera transform.
    @State private var enteringScene: Bool = true

    /// Cumulative drag translation last seen during a look gesture
    /// -- used to derive a per-frame delta. SwiftUI's DragGesture
    /// reports cumulative translation, so the difference between
    /// successive callbacks is the actual finger motion since
    /// last frame.
    @State private var lookAnchor: CGSize = .zero

    /// True once the current touch has moved more than the tap
    /// threshold -- distinguishes a tap (no movement) from a
    /// drag-to-look. Cleared in onEnded.
    @State private var dragMoved: Bool = false

    /// CoreMotion manager that drives VR-mode look. Created lazily
    /// inside the View; the start/stop calls live in toggleVR.
    @State private var motionManager: CMMotionManager = CMMotionManager()

    private func applyLook(translation: CGSize) {
        let delta = CGSize(
            width : translation.width  - lookAnchor.width,
            height: translation.height - lookAnchor.height
        )
        lookAnchor = translation
        // Suppress while the cinematic entry is still descending --
        // we'd be fighting the move(to:) animation.
        guard !enteringScene else { return }
        player?.applyLookDelta(delta)
    }

    var body: some View {
        ZStack {
            RealityView { content in
                buildScene(content)
            } update: { content in
                _ = content
            }
            .ignoresSafeArea()
            // Sky: prefer the bundled "Sky" photo, fall back to a
            // gradient. RealityKit's scene is transparent where
            // there's no geometry, so the SwiftUI background reads
            // through whenever the player looks above the maze.
            .background(skyBackground)

            #if os(iOS)
            // PUBG-style: full-screen drag-to-look. Sits BELOW the
            // joystick + buttons in the ZStack so thumb taps on
            // those still reach them (SwiftUI hit-tests top-down).
            lookSurface
            controlsOverlay
            #endif

            // Top bar: close on the left, altitude steppers + VR +
            // Solve on the right. Down on the inside, up on the
            // outside, so the pair reads as "the up arrow lifts
            // you higher".
            VStack {
                HStack(spacing: 0) {
                    closeButton
                    Spacer()
                    flyDownButton
                    flyUpButton
                    vrToggle
                    solveToggle
                }
                Spacer()
            }

            // Win overlay
            if let player, player.won {
                winOverlay
            }
        }
        .onDisappear {
            // Cut off the motion stream when leaving walk mode --
            // the manager keeps running otherwise, draining
            // battery for nothing.
            motionManager.stopDeviceMotionUpdates()
            player?.stopVR()
        }
    }

    // MARK: scene build

    @MainActor
    private func buildScene(_ content: any RealityViewContentProtocol) {
        let mazeW = Float(maze.width)  * cellSize
        let mazeH = Float(maze.height) * cellSize
        let span  = max(mazeW, mazeH)

        // floor -- sits 1 cm below y=0 so it doesn't share depth
        // with the wall side faces at their base. Co-occupied
        // depth at the bottom edge of every wall was causing a
        // visible flicker stripe along each wall-floor seam --
        // dropping the floor 1cm separates them cleanly.
        let floor = ModelEntity(
            mesh: .generatePlane(width: mazeW, depth: mazeH),
            materials: [floorMaterial()]
        )
        floor.position = SIMD3(mazeW / 2, -0.01, mazeH / 2)
        content.add(floor)

        // walls -- procedural leaf-noise hedge texture
        let wallMat = hedgeMaterial()
        let wallRoot = Entity()
        wallRoot.name = "walls"
        content.add(wallRoot)

        var aabbs: [WallAABB] = []
        let (slots, corners) = wallSlotsAndCorners()
        for (cx, cz, wx, wz) in slots {
            let mesh   = MeshResource.generateBox(size: SIMD3(wx, wallHeight, wz))
            let entity = ModelEntity(mesh: mesh, materials: [wallMat])
            entity.position = SIMD3(cx, wallHeight / 2, cz)
            wallRoot.addChild(entity)
            aabbs.append(WallAABB(
                minX: cx - wx / 2, maxX: cx + wx / 2,
                minZ: cz - wz / 2, maxZ: cz + wz / 2
            ))
        }

        // Corner pillars at TRUE corners. Use a TRIMMED hedge
        // texture for the pillar material: crop a vertical strip
        // of the hedge image whose width matches the pillar's
        // share of the cell (wallT / cellSize) so that, when UV
        // 0..1 is mapped onto the pillar's wallT-wide face, the
        // pixel density matches the surrounding wall slabs. No
        // texture stretching, no content density mismatch, just
        // a thin slice of real hedge.
        let pillarMat = pillarMaterial()
        let cornerMesh = MeshResource.generateBox(size: SIMD3(
            wallThickness, wallHeight, wallThickness
        ))
        for (cx, cz) in corners {
            let pillar = ModelEntity(mesh: cornerMesh, materials: [pillarMat])
            pillar.position = SIMD3(cx, wallHeight / 2, cz)
            wallRoot.addChild(pillar)
            aabbs.append(WallAABB(
                minX: cx - wallThickness / 2, maxX: cx + wallThickness / 2,
                minZ: cz - wallThickness / 2, maxZ: cz + wallThickness / 2
            ))
        }
        walls = aabbs

        // entrance / exit pads
        addPad(into: content,
               x: Float(maze.entrance.x) * cellSize + cellSize / 2,
               z: cellSize / 2,
               color: .systemBlue)
        addPad(into: content,
               x: Float(maze.exit.x) * cellSize + cellSize / 2,
               z: mazeH - cellSize / 2,
               color: .systemGreen)

        // Solution path container -- empty at start; the Solve
        // toggle rebuilds the children from the player's CURRENT
        // cell each time it's switched on, so "show me the way
        // out" always means "from here".
        solutionEntity.name = "solution"
        solutionEntity.isEnabled = false
        content.add(solutionEntity)

        // sun -- warmer, brighter, casts soft shadows down the
        // corridors. Outdoor daylight feel.
        let sun = DirectionalLight()
        sun.light.intensity = 6500
        // Slight golden warmth -- pure white reads as overcast.
        sun.light.color = .init(red: 1.0, green: 0.96, blue: 0.86, alpha: 1.0)
        sun.shadow = DirectionalLightComponent.Shadow(
            maximumDistance: max(50, span * 1.5),
            depthBias      : 6
        )
        sun.orientation = simd_quatf(angle: -.pi / 3, axis: [1, 0, 0])
                        * simd_quatf(angle:  .pi / 6, axis: [0, 1, 0])
        sun.position    = SIMD3(mazeW / 2, span * 1.5, mazeH / 2)
        content.add(sun)

        // Soft fill from the sky to keep shadowed corridors from
        // going pitch black. Cool tone balances the warm sun.
        let fill = DirectionalLight()
        fill.light.intensity = 1800
        fill.light.color = .init(red: 0.7, green: 0.8, blue: 1.0, alpha: 1.0)
        fill.orientation = simd_quatf(angle: .pi / 4, axis: [1, 0, 0])
        content.add(fill)

        // Clouds drifting overhead -- alpha-blended planes that
        // face down so the player sees them when looking up.
        addClouds(into: content, mazeW: mazeW, mazeH: mazeH, span: span)

        // camera + player
        // 90° is the classic "comfortable wide" FPS FOV -- spacious
        // in narrow corridors but well short of the fish-eye
        // distortion that creeps in past ~100°.
        cameraEntity.camera.fieldOfViewInDegrees = 90
        // Add to scene FIRST. RealityKit's animation system needs
        // the entity to be in a scene before move(to:) will animate;
        // otherwise the call is a no-op and the camera just snaps
        // when the next per-frame update hits.
        content.add(cameraEntity)

        #if os(iOS)
        // First-person: stand at the entrance cell.
        let startX = Float(maze.entrance.x) * cellSize + cellSize / 2
        let startZ = cellSize / 2
        // Max altitude scales to the maze size -- enough to see
        // the whole layout from above when fully ascended.
        let maxAlt = max(span * 0.9, 8)
        // Pick a starting yaw that points down an open corridor so
        // we don't open the walk facing a wall. South / east / west
        // priority (north would walk back out the entrance).
        let startYaw = openingYaw(forEntrance: maze.entrance)
        let p = PlayerState(
            start      : SIMD3(startX, eyeHeight, startZ),
            yaw        : startYaw,
            walls      : aabbs,
            maze       : maze,
            exitCellX  : maze.exit.x,
            exitCellZ  : maze.height - 1,
            maxAltitude: maxAlt,
            wallHeight : wallHeight
        )
        player = p

        // ---- cinematic entry ----
        // Phase 1: open with a STRAIGHT-DOWN view above the maze
        //          center -- matches the 2D first page (maze
        //          centered, no rotation).
        // Phase 2: smoothly translate to the player's eye-level
        //          starting position over a few seconds. The
        //          camera stays looking straight down throughout
        //          -- no twisting or turning during the descent.
        // Phase 3: brief pitch-up so we hand off control with the
        //          camera facing down an open corridor.

        let lookDown = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))

        // Open at altitude high enough to fit the maze in both
        // axes on a portrait device. mazeH*0.6 fits a tall maze
        // vertically at FOV=90°; mazeW*1.2 keeps a square / wider
        // maze from getting clipped horizontally.
        let openingY  = max(mazeH * 0.6, mazeW * 1.2)
        let openingPos = SIMD3<Float>(mazeW / 2, openingY, mazeH / 2)
        cameraEntity.transform = Transform(
            scale      : .one,
            rotation   : lookDown,
            translation: openingPos
        )

        let descendTransform = Transform(
            scale      : .one,
            rotation   : lookDown,           // STILL looking straight down
            translation: p.position
        )
        let endRotation = simd_quatf(angle: p.yaw,   axis: [0, 1, 0])
                        * simd_quatf(angle: p.pitch, axis: [1, 0, 0])
        let endTransform = Transform(
            scale      : .one,
            rotation   : endRotation,
            translation: p.position
        )

        // 1-second hold on the overhead view before the descent
        // begins -- gives the eye a beat to take in the full
        // bird's-eye layout before things start moving.
        let openingHold   : TimeInterval = 1.0
        let descendDuration: TimeInterval = 3.0
        let pitchDuration  : TimeInterval = 0.6

        Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: UInt64(openingHold * 1_000_000_000)
            )
            self.cameraEntity.move(
                to            : descendTransform,
                relativeTo    : nil,
                duration      : descendDuration,
                timingFunction: .easeInOut
            )
            try? await Task.sleep(
                nanoseconds: UInt64(descendDuration * 1_000_000_000)
            )
            self.cameraEntity.move(
                to            : endTransform,
                relativeTo    : nil,
                duration      : pitchDuration,
                timingFunction: .easeInOut
            )
            try? await Task.sleep(
                nanoseconds: UInt64(pitchDuration * 1_000_000_000)
            )
            self.enteringScene = false
        }
        #else
        // Overhead-tilted on macOS until WASD/mouselook lands.
        let camY = span * 1.4
        let camZ = mazeH + span * 0.9
        cameraEntity.position = SIMD3(mazeW / 2, camY, camZ)
        cameraEntity.look(at: SIMD3(mazeW / 2, 0, mazeH / 2),
                          from: cameraEntity.position,
                          relativeTo: nil)
        #endif

        // Per-frame update: drive the camera from PlayerState.
        // Skipped while the cinematic entry move(to:) is running
        // so we don't fight the animation for the camera transform.
        #if os(iOS)
        _ = content.subscribe(to: SceneEvents.Update.self) { event in
            Task { @MainActor in
                guard let player = self.player else { return }
                guard !self.enteringScene else { return }
                player.tick(dt: Float(event.deltaTime))
                self.cameraEntity.position = player.position
                let qYaw   = simd_quatf(angle: player.yaw,   axis: [0, 1, 0])
                let qPitch = simd_quatf(angle: player.pitch, axis: [1, 0, 0])
                self.cameraEntity.orientation = qYaw * qPitch
            }
        }
        #endif
    }

    /// Pick the starting yaw so we open the walk view facing an
    /// OPEN corridor instead of a wall. Priority: south (into the
    /// maze), then east, then west; default south. North isn't
    /// considered -- that's back out the entrance gate.
    /// Yaw convention here:
    ///   yaw = 0    → facing -Z (north)
    ///   yaw = π    → facing +Z (south)
    ///   yaw = -π/2 → facing +X (east)
    ///   yaw = +π/2 → facing -X (west)
    private func openingYaw(forEntrance entrance: Coord) -> Float {
        let here = Coord(x: entrance.x, y: 0)
        func openTo(_ to: Coord) -> Bool {
            guard to.x >= 0, to.x < maze.width,
                  to.y >= 0, to.y < maze.height
            else { return false }
            return !maze.wall(between: here, to)
        }
        if openTo(Coord(x: here.x,     y: here.y + 1)) { return  .pi      }   // south
        if openTo(Coord(x: here.x + 1, y: here.y))     { return -(.pi / 2) }   // east
        if openTo(Coord(x: here.x - 1, y: here.y))     { return  .pi / 2  }   // west
        return .pi
    }

    /// Tear down the existing solution-path children and rebuild
    /// from the player's current cell. Called when the Solve
    /// toggle flips on so the line always starts under the
    /// player.
    @MainActor
    private func rebuildSolutionPath() {
        guard let player else { return }
        // Drop any previously-built segment entities.
        for child in solutionEntity.children.map({ $0 }) {
            child.removeFromParent()
        }
        let path = player.solutionFromHere()
        buildSolutionPath(into: solutionEntity, path: path)
    }

    /// Build the solution path as a chain of thin elongated boxes
    /// hovering just above the floor. Uses an unlit material so
    /// the line "glows" -- it ignores scene lighting and reads
    /// brightly even in the shadowed corridors. Caller supplies
    /// the cell list so the overlay can show "from where you are
    /// to the exit" instead of always starting at the entrance.
    @MainActor
    private func buildSolutionPath(into root: Entity, path: [Coord]) {
        guard path.count >= 2 else { return }
        let mat = UnlitMaterial(color: .cyan)
        let lineWidth: Float = 0.10
        let lineY    : Float = 0.04

        func center(_ c: Coord) -> SIMD3<Float> {
            SIMD3(
                Float(c.x) * cellSize + cellSize / 2,
                lineY,
                Float(c.y) * cellSize + cellSize / 2
            )
        }

        for i in 0 ..< path.count - 1 {
            let a = center(path[i])
            let b = center(path[i + 1])
            let mid    = (a + b) * 0.5
            let dx     = b.x - a.x
            let dz     = b.z - a.z
            let length = sqrt(dx * dx + dz * dz)
            if length < 0.001 { continue }
            let yaw    = atan2(dx, dz)

            // A box's default depth axis is +Z, so a yaw rotation
            // around Y aligns that depth axis with (dx, 0, dz).
            let mesh = MeshResource.generateBox(
                size: SIMD3(lineWidth, lineWidth, length)
            )
            let seg = ModelEntity(mesh: mesh, materials: [mat])
            seg.position    = mid
            seg.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            root.addChild(seg)

            // Joint pad at the elbow so corners look continuous.
            let elbow = ModelEntity(
                mesh: .generateBox(size: SIMD3(lineWidth, lineWidth, lineWidth)),
                materials: [mat]
            )
            elbow.position = b
            root.addChild(elbow)
        }
    }

    @MainActor
    private func addPad(into content: any RealityViewContentProtocol,
                        x: Float, z: Float, color: SystemColor)
    {
        let mat = SimpleMaterial(color: color, isMetallic: false)
        let pad = ModelEntity(
            mesh: .generateBox(size: SIMD3(cellSize * 0.85, 0.02, cellSize * 0.85)),
            materials: [mat]
        )
        pad.position = SIMD3(x, 0.011, z)
        content.add(pad)
    }

    /// Build a wallT × wallH × wallT pillar with custom UVs that
    /// show only a `uvScale`-wide slice of the bound texture on
    /// each side face. Standard MeshResource.generateBox would map
    /// the full 0..1 texture onto every face -- on the pillar's
    /// 0.18-wide face that squashes the hedge image into a stretched
    /// stripe. Mapping UV.u from 0..uvScale matches the texture
    /// density of the surrounding wall slabs (whose visible faces
    /// span cellSize and so use uvU = 1.0 over cellSize).
    ///
    /// Box origin is at the FOOT (Y=0) and centered in X/Z, so the
    /// caller positions it by setting `entity.position` to the
    /// floor-level grid intersection.
    @MainActor
    static func makePillarMesh(thickness: Float,
                               height   : Float,
                               uvScale  : Float) -> MeshResource
    {
        let h: Float = thickness / 2
        let H: Float = height
        let u: Float = uvScale       // ~0.22 -- u extent on side faces
        let v: Float = 1.0           // full v on side faces (vertical)

        // 24 vertices, 4 per face × 6 faces; order: +X, -X, +Y, -Y, +Z, -Z
        let positions: [SIMD3<Float>] = [
            // +X
            SIMD3( h, 0, -h), SIMD3( h, 0,  h), SIMD3( h, H,  h), SIMD3( h, H, -h),
            // -X
            SIMD3(-h, 0,  h), SIMD3(-h, 0, -h), SIMD3(-h, H, -h), SIMD3(-h, H,  h),
            // +Y (top)
            SIMD3(-h, H, -h), SIMD3( h, H, -h), SIMD3( h, H,  h), SIMD3(-h, H,  h),
            // -Y (bottom)
            SIMD3(-h, 0,  h), SIMD3( h, 0,  h), SIMD3( h, 0, -h), SIMD3(-h, 0, -h),
            // +Z
            SIMD3( h, 0,  h), SIMD3(-h, 0,  h), SIMD3(-h, H,  h), SIMD3( h, H,  h),
            // -Z
            SIMD3(-h, 0, -h), SIMD3( h, 0, -h), SIMD3( h, H, -h), SIMD3(-h, H, -h),
        ]

        let normals: [SIMD3<Float>] = [
            SIMD3( 1, 0, 0), SIMD3( 1, 0, 0), SIMD3( 1, 0, 0), SIMD3( 1, 0, 0),
            SIMD3(-1, 0, 0), SIMD3(-1, 0, 0), SIMD3(-1, 0, 0), SIMD3(-1, 0, 0),
            SIMD3( 0, 1, 0), SIMD3( 0, 1, 0), SIMD3( 0, 1, 0), SIMD3( 0, 1, 0),
            SIMD3( 0,-1, 0), SIMD3( 0,-1, 0), SIMD3( 0,-1, 0), SIMD3( 0,-1, 0),
            SIMD3( 0, 0, 1), SIMD3( 0, 0, 1), SIMD3( 0, 0, 1), SIMD3( 0, 0, 1),
            SIMD3( 0, 0,-1), SIMD3( 0, 0,-1), SIMD3( 0, 0,-1), SIMD3( 0, 0,-1),
        ]

        // Side faces use u × v slice; top/bottom show a u × u slice
        // (small square -- rarely visible at altitude anyway).
        let uvs: [SIMD2<Float>] = [
            // +X
            SIMD2(0, v), SIMD2(u, v), SIMD2(u, 0), SIMD2(0, 0),
            // -X
            SIMD2(0, v), SIMD2(u, v), SIMD2(u, 0), SIMD2(0, 0),
            // +Y top
            SIMD2(0, 0), SIMD2(u, 0), SIMD2(u, u), SIMD2(0, u),
            // -Y bottom
            SIMD2(0, 0), SIMD2(u, 0), SIMD2(u, u), SIMD2(0, u),
            // +Z
            SIMD2(0, v), SIMD2(u, v), SIMD2(u, 0), SIMD2(0, 0),
            // -Z
            SIMD2(0, v), SIMD2(u, v), SIMD2(u, 0), SIMD2(0, 0),
        ]

        var indices: [UInt32] = []
        for face: UInt32 in 0..<6 {
            let b = face * 4
            indices.append(contentsOf: [b, b + 1, b + 2, b, b + 2, b + 3])
        }

        var d = MeshDescriptor(name: "Pillar")
        d.positions          = MeshBuffers.Positions(positions)
        d.normals            = MeshBuffers.Normals(normals)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        d.primitives         = .triangles(indices)
        return try! MeshResource.generate(from: [d])
    }

    /// Walls + pillars in one pass.
    ///
    /// A pillar is needed ONLY at intersections where walls along
    /// both axes (X-run and Z-run) converge -- i.e. true L / T / +
    /// junctions. At "continuation" points where two collinear
    /// slabs meet (e.g. two top-edge walls at adjacent cells with
    /// no perpendicular wall between them), the slabs touch each
    /// other directly and no pillar is placed -- otherwise the
    /// pillar's wallT-wide face would render the full hedge
    /// texture squashed into 0.18 units, which reads as a visible
    /// vertical seam in the middle of the wall.
    ///
    /// Each slab is shortened by `wallThickness/2` ONLY at ends
    /// where a pillar is placed; ends that are collinear
    /// continuations stay flush with the grid line so adjacent
    /// slabs meet seam-to-seam.
    private func wallSlotsAndCorners() ->
        (slots: [(Float, Float, Float, Float)], corners: [(Float, Float)])
    {
        struct Run {
            let start: SIMD2<Int>
            let end  : SIMD2<Int>
            let isXRun: Bool   // true = wall length runs along X axis
        }
        var runs    = [Run]()
        var xKeys   = Set<SIMD2<Int>>()
        var zKeys   = Set<SIMD2<Int>>()

        @inline(__always) func addX(_ s: SIMD2<Int>, _ e: SIMD2<Int>) {
            runs.append(Run(start: s, end: e, isXRun: true))
            xKeys.insert(s); xKeys.insert(e)
        }
        @inline(__always) func addZ(_ s: SIMD2<Int>, _ e: SIMD2<Int>) {
            runs.append(Run(start: s, end: e, isXRun: false))
            zKeys.insert(s); zKeys.insert(e)
        }

        // Top edge (X-axis runs at gy=0)
        for x in 0..<maze.width where x != maze.entrance.x {
            addX(SIMD2(x, 0), SIMD2(x + 1, 0))
        }
        // Bottom edge (X-axis runs at gy=maze.height)
        for x in 0..<maze.width where x != maze.exit.x {
            addX(SIMD2(x, maze.height), SIMD2(x + 1, maze.height))
        }
        // Left + right edges (Z-axis runs)
        for y in 0..<maze.height {
            addZ(SIMD2(0,          y), SIMD2(0,          y + 1))
            addZ(SIMD2(maze.width, y), SIMD2(maze.width, y + 1))
        }
        // Interior walls
        for y in 0..<maze.height {
            for x in 0..<maze.width {
                let here = Coord(x: x, y: y)
                if x + 1 < maze.width,
                   maze.wall(between: here, Coord(x: x + 1, y: y))
                {
                    addZ(SIMD2(x + 1, y), SIMD2(x + 1, y + 1))
                }
                if y + 1 < maze.height,
                   maze.wall(between: here, Coord(x: x, y: y + 1))
                {
                    addX(SIMD2(x, y + 1), SIMD2(x + 1, y + 1))
                }
            }
        }

        // True corners = both axes converge at this intersection.
        let pillars = xKeys.intersection(zKeys)

        // Build slot tuples with per-end shortening based on
        // whether each end has a pillar.
        var slots = [(Float, Float, Float, Float)]()
        let half  = wallThickness / 2
        for r in runs {
            let startShort = pillars.contains(r.start) ? half : 0
            let endShort   = pillars.contains(r.end)   ? half : 0
            if r.isXRun {
                let gxA = Float(r.start.x) * cellSize + startShort
                let gxB = Float(r.end.x)   * cellSize - endShort
                let cz  = Float(r.start.y) * cellSize
                slots.append(((gxA + gxB) / 2, cz, gxB - gxA, wallThickness))
            } else {
                let gzA = Float(r.start.y) * cellSize + startShort
                let gzB = Float(r.end.y)   * cellSize - endShort
                let cx  = Float(r.start.x) * cellSize
                slots.append((cx, (gzA + gzB) / 2, wallThickness, gzB - gzA))
            }
        }

        let corners = pillars.map {
            (Float($0.x) * cellSize, Float($0.y) * cellSize)
        }
        return (slots, corners)
    }

    private func wallSlots() -> [(Float, Float, Float, Float)] {
        var slots: [(Float, Float, Float, Float)] = []
        let mazeW = Float(maze.width)  * cellSize
        let mazeH = Float(maze.height) * cellSize

        // Legacy path -- kept temporarily for reference; not used.
        let slabLen = cellSize - wallThickness

        for x in 0..<maze.width where x != maze.entrance.x {
            slots.append((Float(x) * cellSize + cellSize / 2,
                          0, slabLen, wallThickness))
        }
        for x in 0..<maze.width where x != maze.exit.x {
            slots.append((Float(x) * cellSize + cellSize / 2,
                          mazeH, slabLen, wallThickness))
        }
        for y in 0..<maze.height {
            slots.append((0,     Float(y) * cellSize + cellSize / 2,
                          wallThickness, slabLen))
            slots.append((mazeW, Float(y) * cellSize + cellSize / 2,
                          wallThickness, slabLen))
        }
        for y in 0..<maze.height {
            for x in 0..<maze.width {
                let here = Coord(x: x, y: y)
                if x + 1 < maze.width {
                    let east = Coord(x: x + 1, y: y)
                    if maze.wall(between: here, east) {
                        slots.append((Float(x + 1) * cellSize,
                                      Float(y) * cellSize + cellSize / 2,
                                      wallThickness, slabLen))
                    }
                }
                if y + 1 < maze.height {
                    let south = Coord(x: x, y: y + 1)
                    if maze.wall(between: here, south) {
                        slots.append((Float(x) * cellSize + cellSize / 2,
                                      Float(y + 1) * cellSize,
                                      slabLen, wallThickness))
                    }
                }
            }
        }
        return slots
    }

    // MARK: overlays

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.largeTitle)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.6))
                .padding()
        }
        .accessibilityLabel("Close 3D view")
    }

    /// Step the camera up by ~1.25× hedge height. Tap repeatedly
    /// to climb -- starts at ground, max is the maze span (a near-
    /// bird's-eye view). Look-yaw + pitch stay live throughout.
    private var flyUpButton: some View {
        let atMax = (player?.targetAltitude ?? 0) >= (player?.maxAltitude ?? 0) - 0.01
        return Button {
            player?.raiseAltitude(by: flyStep)
        } label: {
            Image(systemName: "arrow.up")
                .font(.largeTitle)
                .padding(10)
                .background(Circle().fill(.black.opacity(0.55)))
                .foregroundStyle(.white)
                .padding(.vertical)
        }
        .disabled(atMax)
        .opacity(atMax ? 0.4 : 1.0)
        .accessibilityLabel("Fly up")
    }

    /// Step the camera down. At ground level the button disables.
    private var flyDownButton: some View {
        let atGround = (player?.targetAltitude ?? 0) <= 0.01
        return Button {
            player?.lowerAltitude(by: flyStep)
        } label: {
            Image(systemName: "arrow.down")
                .font(.largeTitle)
                .padding(10)
                .background(Circle().fill(.black.opacity(0.55)))
                .foregroundStyle(.white)
                .padding(.vertical)
        }
        .disabled(atGround)
        .opacity(atGround ? 0.4 : 1.0)
        .accessibilityLabel("Fly down")
    }

    /// World units per altitude tap. Tuned so 1 tap = ~1.25× hedge
    /// (puts you just clear of the hedges from the ground).
    private let flyStep: Float = 2.5

    /// VR-look toggle. While on, device motion (azimuth + tilt)
    /// drives the camera yaw + pitch. Drag-to-look is suppressed.
    /// Tap-to-walk and the D-pad continue to work -- only the
    /// view rotation is gyro-driven.
    private var vrToggle: some View {
        Button {
            toggleVR()
        } label: {
            Image(systemName: "arkit")
                .font(.largeTitle)
                .padding(10)
                .background(Circle().fill(.black.opacity(0.55)))
                .foregroundStyle(
                    (player?.vrEnabled ?? false) ? .yellow : .white
                )
                .padding()
        }
        .accessibilityLabel(
            (player?.vrEnabled ?? false) ? "Disable VR look" : "Enable VR look"
        )
    }

    private func toggleVR() {
        guard let player else { return }
        if player.vrEnabled {
            player.stopVR()
            motionManager.stopDeviceMotionUpdates()
        } else {
            guard motionManager.isDeviceMotionAvailable else { return }
            player.startVR()
            motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
            // Capture the player class reference so the closure
            // doesn't depend on the View's @State accessor (which
            // freezes at closure-creation time but the class ref
            // stays stable across re-renders).
            let p = player
            motionManager.startDeviceMotionUpdates(to: .main) { motion, _ in
                guard let m = motion else { return }
                Task { @MainActor in
                    p.applyMotion(m)
                }
            }
        }
    }

    /// Top-right toggle that shows / hides the solution-path
    /// overlay. On every switch-on the path is rebuilt from the
    /// player's CURRENT cell to the exit (BFS), so "show the way
    /// out" tracks the player as they explore.
    private var solveToggle: some View {
        Button {
            showingSolution.toggle()
            if showingSolution {
                rebuildSolutionPath()
            }
            solutionEntity.isEnabled = showingSolution
        } label: {
            Image(systemName: "scope")
                .font(.largeTitle)
                .padding(10)
                .background(
                    Circle().fill(.black.opacity(0.55))
                )
                .foregroundStyle(showingSolution ? .cyan : .white)
                .padding()
        }
        .accessibilityLabel(showingSolution
                            ? "Hide solution path"
                            : "Show solution path")
    }

    #if os(iOS)
    /// Full-screen transparent layer that captures drag gestures
    /// for camera rotation AND tap gestures for tap-to-walk. The
    /// gesture distinguishes via translation magnitude: anything
    /// under the tap threshold ends as a tap (handleTap); anything
    /// over starts a look-rotation that ignores the lift.
    private var lookSurface: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !dragMoved {
                                let dx = value.translation.width
                                let dy = value.translation.height
                                if abs(dx) > 8 || abs(dy) > 8 {
                                    dragMoved = true
                                    // Reset anchor so the first
                                    // applyLook delta is small.
                                    lookAnchor = value.translation
                                }
                            }
                            if dragMoved {
                                applyLook(translation: value.translation)
                            }
                        }
                        .onEnded { value in
                            if !dragMoved {
                                handleTap(at: value.location,
                                          viewSize: geo.size)
                            }
                            dragMoved  = false
                            lookAnchor = .zero
                        }
                )
        }
    }

    /// Convert a screen-space tap into a maze cell and ask the
    /// player to walk there. Builds a ray from the camera through
    /// the tap point, intersects with the floor (y=0) plane, and
    /// floors the world XZ to find the cell.
    private func handleTap(at screenPoint: CGPoint, viewSize: CGSize) {
        guard let player else { return }
        guard !enteringScene else { return }
        guard !player.isFlying else { return }
        guard viewSize.width > 0, viewSize.height > 0 else { return }

        let xNDC =  Float(screenPoint.x / viewSize.width)  * 2 - 1
        let yNDC = -(Float(screenPoint.y / viewSize.height) * 2 - 1)

        // Camera vertical FOV is 90° → tan(half) = 1.
        let tanFovV = Float(1.0)
        let aspect  = Float(viewSize.width / viewSize.height)
        let tanFovH = tanFovV * aspect

        // Ray direction in camera local space (camera looks -Z).
        let dirLocal = simd_normalize(SIMD3<Float>(
            xNDC * tanFovH,
            yNDC * tanFovV,
            -1
        ))
        let dirWorld = cameraEntity.orientation.act(dirLocal)
        let origin   = cameraEntity.position

        // Floor at y=0 → t = -origin.y / dir.y. Need ray going
        // downward (dir.y < 0) for an intersection at or below.
        guard dirWorld.y < -1e-4 else { return }
        let t = -origin.y / dirWorld.y
        guard t > 0 else { return }
        let hit = origin + dirWorld * t

        let cx = Int(floor(hit.x / cellSize))
        let cz = Int(floor(hit.z / cellSize))
        guard cx >= 0, cx < maze.width,
              cz >= 0, cz < maze.height
        else { return }

        player.walkTo(Coord(x: cx, y: cz))
    }

    /// Bottom-left D-pad: 4 cardinal step buttons. Each tap moves
    /// the player exactly one cell in the indicated direction
    /// (relative to the player's facing); blocked moves no-op.
    /// Look gestures still work everywhere on the rest of the
    /// screen via the look surface below.
    private var controlsOverlay: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                DPad { fwd, strafe in
                    guard !enteringScene else { return }
                    player?.step(forward: fwd, strafe: strafe)
                    Haptics.shared.carveTick()
                }
                .padding(.leading, 24)
                .padding(.bottom , 28)

                Spacer()
            }
        }
    }
    #endif

    private var winOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(.white)
            Text("You escaped!")
                .font(.title.bold())
                .foregroundStyle(.white)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(40)
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 20))
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.35))
        .transition(.opacity.combined(with: .scale))
    }

    // MARK: theme color

    private var hedgeColor: SystemColor {
        #if os(iOS)
        return UIColor(red: 0.20, green: 0.45, blue: 0.20, alpha: 1.0)
        #elseif os(macOS)
        return NSColor(red: 0.20, green: 0.45, blue: 0.20, alpha: 1.0)
        #else
        return .green
        #endif
    }

    private var skyGradientColors: [Color] {
        if scheme == .dark {
            return [
                Color(red: 0.30, green: 0.42, blue: 0.55),
                Color(red: 0.08, green: 0.14, blue: 0.25)
            ]
        } else {
            return [
                Color(red: 0.65, green: 0.80, blue: 0.95),
                Color(red: 0.25, green: 0.50, blue: 0.85)
            ]
        }
    }

    /// Background view: bundled Sky photo when available, else a
    /// scheme-aware gradient. Wrapping in a ViewBuilder lets us
    /// swap a real photograph in just by adding the asset.
    @ViewBuilder
    private var skyBackground: some View {
        #if os(iOS)
        if let _ = UIImage(named: "Sky") {
            Image("Sky")
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(colors: skyGradientColors,
                           startPoint: .bottom, endPoint: .top)
        }
        #elseif os(macOS)
        if NSImage(named: "Sky") != nil {
            Image("Sky")
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(colors: skyGradientColors,
                           startPoint: .bottom, endPoint: .top)
        }
        #else
        LinearGradient(colors: skyGradientColors,
                       startPoint: .bottom, endPoint: .top)
        #endif
    }

    // MARK: procedural materials

    @MainActor
    private func hedgeMaterial() -> RealityKit.Material {
        let tex = loadAssetTextureWithMipmaps("Hedge")
                 ?? generateLeafTexture()
        if let tex {
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(texture: .init(tex))
            m.roughness = .init(floatLiteral: 0.95)
            m.metallic  = .init(floatLiteral: 0.00)
            return m
        }
        return SimpleMaterial(color: hedgeColor,
                              roughness: 0.85, isMetallic: false)
    }

    @MainActor
    private func floorMaterial() -> RealityKit.Material {
        let tex = loadAssetTextureWithMipmaps("Floor")
                 ?? generateFloorTexture()
        if let tex {
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(texture: .init(tex))
            m.roughness = .init(floatLiteral: 0.95)
            m.metallic  = .init(floatLiteral: 0.00)
            return m
        }
        return SimpleMaterial(color: .init(white: 0.55, alpha: 1.0),
                              roughness: 0.95, isMetallic: false)
    }

    /// Material for corner pillars. Crops the hedge image to a
    /// vertical strip wide enough to match the pillar's share of
    /// a cell -- when standard UV 0..1 is then mapped onto the
    /// pillar's wallT-wide face, leaf-pixel density on the
    /// pillar matches the surrounding wall slabs. No squashed
    /// full-image, no content discontinuity.
    @MainActor
    private func pillarMaterial() -> RealityKit.Material {
        if let tex = pillarTexture() {
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(texture: .init(tex))
            m.roughness = .init(floatLiteral: 0.95)
            m.metallic  = .init(floatLiteral: 0.00)
            return m
        }
        // Fallback to a solid hedge tone.
        let color = SystemColor(red: 0.18, green: 0.34, blue: 0.14, alpha: 1.0)
        return SimpleMaterial(color: color,
                              roughness: 0.95, isMetallic: false)
    }

    @MainActor
    private func pillarTexture() -> TextureResource? {
        // Get the source hedge CGImage (from the asset catalog
        // when present, otherwise the procedural generator's
        // CGImage path).
        let cg: CGImage? = {
            #if os(iOS)
            if let ui = UIImage(named: "Hedge"), let g = ui.cgImage {
                return g
            }
            #elseif os(macOS)
            if let ns = NSImage(named: "Hedge"),
               let g = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                return g
            }
            #endif
            return nil
        }()
        guard let source = cg else { return nil }

        // Crop a centered vertical strip whose horizontal size is
        // wallT/cellSize fraction of the source. Vertical full
        // height -- pillar has the same wallH as walls, so the
        // vertical density already matches.
        let widthFraction = CGFloat(wallThickness / cellSize)
        let cropW = max(1, Int(CGFloat(source.width) * widthFraction))
        let cropH = source.height
        let cropX = (source.width - cropW) / 2
        let rect  = CGRect(x: cropX, y: 0, width: cropW, height: cropH)
        guard let cropped = source.cropping(to: rect) else { return nil }

        return try? TextureResource(
            image  : cropped,
            options: TextureResource.CreateOptions(
                semantic   : .color,
                mipmapsMode: .allocateAndGenerateAll
            )
        )
    }

    /// Asset-catalog → CGImage → TextureResource with explicit
    /// mipmap generation. The default load(named:) path doesn't
    /// always allocate mipmaps, which makes high-frequency
    /// textures (dense leaves, fine pebbles) sparkle / flicker
    /// when the surface is sampled at distance or steep angles.
    /// Allocating + generating all mip levels lets the GPU pick
    /// the right LOD per pixel.
    @MainActor
    private func loadAssetTextureWithMipmaps(_ name: String) -> TextureResource? {
        #if os(iOS)
        guard let ui = UIImage(named: name), let cg = ui.cgImage else {
            return nil
        }
        return try? TextureResource(
            image  : cg,
            options: TextureResource.CreateOptions(
                semantic   : .color,
                mipmapsMode: .allocateAndGenerateAll
            )
        )
        #elseif os(macOS)
        guard let ns = NSImage(named: name),
              let cg = ns.cgImage(
                forProposedRect: nil, context: nil, hints: nil
              )
        else { return nil }
        return try? TextureResource(
            image  : cg,
            options: TextureResource.CreateOptions(
                semantic   : .color,
                mipmapsMode: .allocateAndGenerateAll
            )
        )
        #else
        return nil
        #endif
    }

    /// Dark-green base with thousands of small leaf-bright specks.
    /// Reads plausibly leafy at any distance and avoids the
    /// "painted block" look of a flat color.
    @MainActor
    private func generateLeafTexture(size: Int = 256) -> TextureResource? {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data            : nil,
            width           : size,
            height          : size,
            bitsPerComponent: 8,
            bytesPerRow     : 0,
            space           : cs,
            bitmapInfo      : CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setFillColor(CGColor(red: 0.07, green: 0.22, blue: 0.08, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

        var rng = SystemRandomNumberGenerator()
        for _ in 0..<3500 {
            let x = Double.random(in: 0..<Double(size), using: &rng)
            let y = Double.random(in: 0..<Double(size), using: &rng)
            let r = Double.random(in: 0.8..<3.5, using: &rng)
            let bright = Double.random(in: 0.0..<1.0, using: &rng)
            ctx.setFillColor(CGColor(
                red  : 0.05 + bright * 0.18,
                green: 0.22 + bright * 0.45,
                blue : 0.05 + bright * 0.15,
                alpha: 1.0
            ))
            ctx.fillEllipse(in: CGRect(
                x: x - r/2, y: y - r/2, width: r, height: r
            ))
        }

        guard let cg = ctx.makeImage() else { return nil }
        return try? TextureResource(
            image  : cg,
            options: TextureResource.CreateOptions(semantic: .color, mipmapsMode: .allocateAndGenerateAll)
        )
    }

    /// Scatter cloud-billboards above the maze. Each is a flat
    /// plane facing down, alpha-blended over the sky gradient.
    /// Looks great when the player looks up while flying.
    @MainActor
    private func addClouds(into content: any RealityViewContentProtocol,
                           mazeW: Float, mazeH: Float, span: Float)
    {
        // Try to load a bundled "Sky" / cloud asset first; fall
        // back to a procedurally generated puffy white shape.
        let cloudTex = (try? TextureResource.load(named: "Sky"))
                     ?? generateCloudTexture()
        guard let cloudTex else { return }

        var mat = UnlitMaterial()
        mat.color = .init(texture: .init(cloudTex))
        // Treat the texture's alpha channel as transparency so the
        // soft cloud edges blend into the sky.
        mat.blending = .transparent(opacity: .init(floatLiteral: 1.0))

        var rng = SystemRandomNumberGenerator()
        let cloudCount = 24
        for _ in 0..<cloudCount {
            let cw = Float.random(in: 8 ..< 22, using: &rng)
            let cd = cw * Float.random(in: 0.55 ..< 0.85, using: &rng)
            let cx = Float.random(in: -span * 0.6 ..< mazeW + span * 0.6, using: &rng)
            let cz = Float.random(in: -span * 0.6 ..< mazeH + span * 0.6, using: &rng)
            let cy = Float.random(in: 28 ..< 55, using: &rng)
            let cloud = ModelEntity(
                mesh: .generatePlane(width: cw, depth: cd),
                materials: [mat]
            )
            cloud.position = SIMD3(cx, cy, cz)
            // Default plane faces +Y (up). Rotate by π around X so
            // the textured side faces -Y (down) toward the player.
            cloud.orientation = simd_quatf(angle: .pi, axis: [1, 0, 0])
            content.add(cloud)
        }
    }

    /// Procedural cloud texture: stacked soft white radial blobs
    /// on a transparent background. Renders as a puffy shape with
    /// soft edges that blend into the sky.
    @MainActor
    private func generateCloudTexture(size: Int = 256) -> TextureResource? {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data            : nil,
            width           : size,
            height          : size,
            bitsPerComponent: 8,
            bytesPerRow     : 0,
            space           : cs,
            bitmapInfo      : CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

        let cw = Double(size)
        var rng = SystemRandomNumberGenerator()
        let bumps = 9
        for _ in 0..<bumps {
            let cx = Double.random(in: cw * 0.20 ..< cw * 0.80, using: &rng)
            let cy = Double.random(in: cw * 0.40 ..< cw * 0.60, using: &rng)
            let radius = Double.random(in: cw * 0.14 ..< cw * 0.28, using: &rng)
            guard let gradient = CGGradient(
                colorsSpace: cs,
                colors    : [
                    CGColor(red: 1, green: 1, blue: 1, alpha: 0.95),
                    CGColor(red: 1, green: 1, blue: 1, alpha: 0.00)
                ] as CFArray,
                locations : [0, 1]
            ) else { return nil }
            ctx.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                endCenter  : CGPoint(x: cx, y: cy), endRadius: CGFloat(radius),
                options    : []
            )
        }

        guard let cg = ctx.makeImage() else { return nil }
        return try? TextureResource(
            image  : cg,
            options: TextureResource.CreateOptions(semantic: .color, mipmapsMode: .allocateAndGenerateAll)
        )
    }

    /// Warm beige base with darker pebbles -- packed-earth path.
    @MainActor
    private func generateFloorTexture(size: Int = 256) -> TextureResource? {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data            : nil,
            width           : size,
            height          : size,
            bitsPerComponent: 8,
            bytesPerRow     : 0,
            space           : cs,
            bitmapInfo      : CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setFillColor(CGColor(red: 0.55, green: 0.50, blue: 0.40, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

        var rng = SystemRandomNumberGenerator()
        for _ in 0..<2200 {
            let x  = Double.random(in: 0..<Double(size), using: &rng)
            let y  = Double.random(in: 0..<Double(size), using: &rng)
            let r  = Double.random(in: 0.8..<3.0, using: &rng)
            let dn = Double.random(in: -0.15..<0.15, using: &rng)
            ctx.setFillColor(CGColor(
                red  : 0.55 + dn,
                green: 0.50 + dn,
                blue : 0.40 + dn,
                alpha: 1.0
            ))
            ctx.fillEllipse(in: CGRect(
                x: x - r/2, y: y - r/2, width: r, height: r
            ))
        }

        guard let cg = ctx.makeImage() else { return nil }
        return try? TextureResource(
            image  : cg,
            options: TextureResource.CreateOptions(semantic: .color, mipmapsMode: .allocateAndGenerateAll)
        )
    }
}

#if os(iOS)
private typealias SystemColor = UIColor
#elseif os(macOS)
private typealias SystemColor = NSColor
#else
private typealias SystemColor = Color
#endif
