import SpriteKit

struct InputState {
    var dx: Int = 0
    var jumpHeld = false
    var jumpPressed = false
}

/// Ninja physics. Units are world points per 1/60 s frame.
final class Player {
    enum Tuning {
        static let radius: CGFloat = 10
        static let groundAccel: CGFloat = 0.0667
        static let airAccel: CGFloat = 0.0444
        static let maxRunSpeed: CGFloat = 3.333
        static let gravityFall: CGFloat = 0.0667
        static let gravityJump: CGFloat = 0.0111
        static let maxJumpFrames = 45
        static let drag: CGFloat = 0.9933
        static let groundFriction: CGFloat = 0.9459
        static let wallFriction: CGFloat = 0.9113
        static let jumpSpeed: CGFloat = 2
        static let maxSurvivableImpact: CGFloat = 6
        static let substeps = 4
        static let maxFallSpeed: CGFloat = 10
    }

    var pos: CGPoint
    var vel = CGPoint.zero
    let r = Tuning.radius

    private(set) var grounded = false
    private(set) var groundNormal = CGPoint(x: 0, y: 1)
    private(set) var wallSide = 0          // -1 wall on the left, 1 on the right
    private(set) var wallSliding = false
    private(set) var facing: CGFloat = 1
    private(set) var runPhase: CGFloat = 0
    private var coyote = 0
    private var jumpBuffer = 0
    private var jumping = false
    private var jumpFrames = 0

    /// Set when a jump happened this frame (for effects).
    private(set) var didJump = false
    private(set) var didWallJump = false
    /// Impact speed of a landing this frame (0 if none).
    private(set) var landImpact: CGFloat = 0

    let node = NinjaNode()

    init(at p: CGPoint) {
        pos = CGPoint(x: p.x, y: p.y - TS / 2 + r + 0.5)
        node.position = pos
    }

    func launch(vy: CGFloat) {
        vel.y = vy
        jumping = false
        grounded = false
        coyote = 0
    }

    /// Advances one frame. Returns true if the ninja died from an impact.
    func step(_ inp: InputState, map: LevelMap) -> Bool {
        let T = Tuning.self
        let ix = CGFloat(inp.dx)
        didJump = false
        didWallJump = false
        landImpact = 0

        if inp.jumpPressed { jumpBuffer = 6 } else if jumpBuffer > 0 { jumpBuffer -= 1 }

        // Wall probes (a little beyond the body so wall jumps feel forgiving).
        let probe = r + 3
        let wallL = map.isSolid(CGPoint(x: pos.x - probe, y: pos.y)) || map.isSolid(CGPoint(x: pos.x - probe, y: pos.y - 6))
        let wallR = map.isSolid(CGPoint(x: pos.x + probe, y: pos.y)) || map.isSolid(CGPoint(x: pos.x + probe, y: pos.y - 6))
        if grounded {
            wallSide = 0
        } else if wallL && wallR {
            wallSide = ix != 0 ? Int(ix) : 1
        } else {
            wallSide = wallR ? 1 : (wallL ? -1 : 0)
        }

        // Horizontal control.
        if ix != 0 {
            let acc = grounded ? T.groundAccel : T.airAccel
            let nv = vel.x + ix * acc
            if abs(nv) <= T.maxRunSpeed || nv * ix < 0 {
                vel.x = nv
            } else if abs(vel.x) < T.maxRunSpeed {
                vel.x = ix * T.maxRunSpeed
            }
            if grounded && vel.x * ix < 0 { vel.x *= T.groundFriction }
            facing = ix
        } else if grounded {
            vel = vel * T.groundFriction
        }

        // Jumping.
        if jumpBuffer > 0 {
            if grounded || coyote > 0 {
                vel.y = T.jumpSpeed
                if abs(groundNormal.x) > 0.1 { vel.x += groundNormal.x * 0.7 }
                startJump()
            } else if wallSide != 0 {
                let away = CGFloat(-wallSide)
                if ix == CGFloat(wallSide) {
                    vel.x = away * 2 / 3
                    vel.y = 1.0
                } else {
                    vel.x = away
                    vel.y = 1.4
                }
                facing = away
                startJump()
                didWallJump = true
            }
        }

        // Gravity: lighter while the jump button is held during a jump.
        let holding = jumping && inp.jumpHeld && jumpFrames < T.maxJumpFrames && vel.y > 0
        if !holding { jumping = false }
        vel.y -= holding ? T.gravityJump : T.gravityFall
        jumpFrames += 1

        // Wall sliding.
        wallSliding = false
        if !grounded && wallSide != 0 && ix == CGFloat(wallSide) && vel.y < 0 {
            vel.y *= T.wallFriction
            wallSliding = true
        }

        if !grounded { vel.x *= T.drag }
        vel.y = max(vel.y, -T.maxFallSpeed)

        // Integrate with substeps and resolve collisions.
        var nowGrounded = false
        var floorImpact: CGFloat = 0
        var died = false
        let inv = 1 / CGFloat(T.substeps)
        for _ in 0..<T.substeps {
            pos += vel * inv
            for n in map.collideCircle(&pos, radius: r) {
                let vn = vel.dot(n)
                if n.y > 0.5 { floorImpact = max(floorImpact, -vn) }
                if vn < 0 {
                    let impact = -vn
                    let limit: CGFloat = T.maxSurvivableImpact - 4.0 / 3.0 * abs(n.y)
                    if abs(n.y) > 0.1 && impact > limit {
                        died = true
                    }
                    vel = vel - n * vn
                }
                if n.y > 0.5 {
                    nowGrounded = true
                    groundNormal = n
                }
            }
        }

        if nowGrounded {
            if !grounded { landImpact = floorImpact }
            grounded = true
            coyote = 5
        } else {
            if grounded { coyote = 5 }
            grounded = false
            if coyote > 0 { coyote -= 1 }
        }

        if grounded {
            runPhase += abs(vel.x) * 0.22
        }
        return died
    }

    private func startJump() {
        jumping = true
        jumpFrames = 0
        jumpBuffer = 0
        coyote = 0
        grounded = false
        didJump = true
    }

    func syncNode(time: CGFloat) {
        node.position = pos
        node.pose(vel: vel, grounded: grounded, wallSliding: wallSliding, wallSide: wallSide,
                  facing: facing, phase: runPhase, time: time)
    }
}

/// Procedurally drawn stick-figure ninja.
final class NinjaNode: SKNode {
    private let body = SKShapeNode()
    private let head = SKShapeNode(circleOfRadius: 3.6)
    private let scarf = SKShapeNode()
    private let figure = SKNode()

    override init() {
        super.init()
        for s in [body, scarf] {
            s.lineWidth = 2
            s.lineCap = .round
            s.lineJoin = .round
            s.isAntialiased = true
        }
        body.strokeColor = Theme.ninja
        scarf.strokeColor = Theme.scarf
        scarf.lineWidth = 1.6
        head.fillColor = Theme.ninja
        head.strokeColor = .clear
        figure.addChild(scarf)
        figure.addChild(body)
        figure.addChild(head)
        addChild(figure)
    }

    required init?(coder: NSCoder) { fatalError() }

    func pose(vel: CGPoint, grounded: Bool, wallSliding: Bool, wallSide: Int,
              facing: CGFloat, phase: CGFloat, time: CGFloat) {
        let speed = abs(vel.x)
        var lean: CGFloat = 0
        var feet: (CGPoint, CGPoint)
        var knees: (CGPoint, CGPoint)
        var hands: (CGPoint, CGPoint)
        var dir = facing

        let hip = CGPoint(x: 0, y: -2)
        if wallSliding {
            dir = CGFloat(wallSide)
            lean = -1.5
            feet = (CGPoint(x: 5, y: -9), CGPoint(x: 2, y: -10))
            knees = (CGPoint(x: 1, y: -5), CGPoint(x: -1, y: -6))
            hands = (CGPoint(x: 6, y: 6), CGPoint(x: 6, y: 2))
        } else if grounded {
            if speed > 0.15 {
                lean = min(speed, 3.3) * 0.7
                let s = sin(phase), c = cos(phase)
                let stride = min(speed * 2.2, 6.5)
                feet = (CGPoint(x: s * stride, y: -10 + max(0, c) * 3),
                        CGPoint(x: -s * stride, y: -10 + max(0, -c) * 3))
                knees = (CGPoint(x: s * stride * 0.5 + 2, y: -6 + max(0, c) * 1.5),
                         CGPoint(x: -s * stride * 0.5 + 2, y: -6 + max(0, -c) * 1.5))
                hands = (CGPoint(x: -s * 5 + lean, y: -1), CGPoint(x: s * 5 + lean, y: -1))
            } else {
                feet = (CGPoint(x: 3, y: -10), CGPoint(x: -3, y: -10))
                knees = (CGPoint(x: 2, y: -6), CGPoint(x: -2, y: -6))
                hands = (CGPoint(x: 3, y: -4), CGPoint(x: -3, y: -4))
            }
        } else if vel.y > 0 {
            lean = clamp(speed * 0.5, 0, 1.5)
            feet = (CGPoint(x: 3, y: -7), CGPoint(x: -2, y: -9))
            knees = (CGPoint(x: 4, y: -3), CGPoint(x: 0, y: -6))
            hands = (CGPoint(x: 4, y: 7), CGPoint(x: -3, y: 6))
        } else {
            lean = clamp(speed * 0.4, 0, 1.2)
            feet = (CGPoint(x: 3, y: -10), CGPoint(x: -3, y: -9))
            knees = (CGPoint(x: 2, y: -6), CGPoint(x: -2, y: -6))
            hands = (CGPoint(x: 6, y: 3), CGPoint(x: -6, y: 4))
        }

        let neck = CGPoint(x: lean, y: 4)
        let shoulder = CGPoint(x: lean * 0.9, y: 3)
        let path = CGMutablePath()
        path.move(to: hip); path.addLine(to: neck)
        path.move(to: hip); path.addLine(to: knees.0); path.addLine(to: feet.0)
        path.move(to: hip); path.addLine(to: knees.1); path.addLine(to: feet.1)
        path.move(to: shoulder); path.addLine(to: shoulder + (hands.0 - shoulder) * 0.5 + CGPoint(x: 0, y: -1)); path.addLine(to: hands.0)
        path.move(to: shoulder); path.addLine(to: shoulder + (hands.1 - shoulder) * 0.5 + CGPoint(x: 0, y: -1)); path.addLine(to: hands.1)
        body.path = path

        let headC = neck + CGPoint(x: lean * 0.3, y: 3.8)
        head.position = headC

        // Scarf trails behind and flutters with speed.
        let flutter = sin(time * 18) * (0.6 + min(vel.length, 4) * 0.4)
        let trail = 5 + min(vel.length, 4) * 1.6
        let knot = headC + CGPoint(x: -2.5, y: 0.8)
        let sp = CGMutablePath()
        sp.move(to: knot)
        sp.addLine(to: knot + CGPoint(x: -trail * 0.55, y: flutter * 0.5 - vel.y * 0.4))
        sp.addLine(to: knot + CGPoint(x: -trail, y: flutter - vel.y * 0.9))
        scarf.path = sp

        figure.xScale = dir
    }
}
