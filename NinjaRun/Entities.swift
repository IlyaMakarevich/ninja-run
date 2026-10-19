import SpriteKit

/// Base class for everything that lives in a level besides tiles and the ninja.
class Entity {
    let node = SKNode()
    var pos: CGPoint
    var alive = true

    init(at p: CGPoint) {
        pos = p
        node.position = p
    }

    func update(_ g: GameScene) {}

    func touchesPlayer(_ g: GameScene, radius: CGFloat) -> Bool {
        g.state == .playing && g.player.pos.distance(to: pos) < radius + g.player.r
    }
}

// MARK: - Pickups and level objects

final class Gold: Entity {
    private let shape = SKShapeNode(rectOf: CGSize(width: 9, height: 9), cornerRadius: 1.5)

    override init(at p: CGPoint) {
        super.init(at: p)
        shape.fillColor = Theme.gold
        shape.strokeColor = Theme.goldDark
        shape.lineWidth = 1.2
        node.addChild(shape)
        let phase = Double(p.x + p.y) * 0.05
        shape.run(.sequence([.wait(forDuration: phase.truncatingRemainder(dividingBy: 1)),
                             .repeatForever(.sequence([.moveBy(x: 0, y: 1.5, duration: 0.6),
                                                       .moveBy(x: 0, y: -1.5, duration: 0.6)]))]))
    }

    override func update(_ g: GameScene) {
        guard alive, touchesPlayer(g, radius: 6) else { return }
        alive = false
        g.collectGold()
        shape.removeAllActions()
        node.run(.sequence([.group([.scale(to: 2, duration: 0.2), .fadeOut(withDuration: 0.2)]), .removeFromParent()]))
    }
}

final class Mine: Entity {
    override init(at p: CGPoint) {
        super.init(at: p)
        let spikes = SKShapeNode()
        let path = CGMutablePath()
        for i in 0..<8 {
            let a = CGFloat(i) * .pi / 4
            path.move(to: CGPoint(x: cos(a) * 3, y: sin(a) * 3))
            path.addLine(to: CGPoint(x: cos(a) * 6.5, y: sin(a) * 6.5))
        }
        spikes.path = path
        spikes.strokeColor = Theme.ninja
        spikes.lineWidth = 1.4
        let core = SKShapeNode(circleOfRadius: 4)
        core.fillColor = Theme.mine
        core.strokeColor = Theme.ninja
        core.lineWidth = 1.2
        node.addChild(spikes)
        node.addChild(core)
        core.run(.repeatForever(.sequence([.fadeAlpha(to: 0.6, duration: 0.5), .fadeAlpha(to: 1, duration: 0.5)])))
    }

    override func update(_ g: GameScene) {
        guard alive, touchesPlayer(g, radius: 4) else { return }
        alive = false
        g.explosion(at: pos, radius: 22)
        node.removeFromParent()
        g.killPlayer()
    }
}

final class ExitSwitch: Entity {
    private let plate = SKShapeNode(rectOf: CGSize(width: 12, height: 12), cornerRadius: 2)
    private let light = SKShapeNode(circleOfRadius: 3)

    override init(at p: CGPoint) {
        super.init(at: p)
        plate.fillColor = Theme.switchOff
        plate.strokeColor = Theme.ninja
        plate.lineWidth = 1.2
        light.fillColor = Theme.accent
        light.strokeColor = .clear
        node.addChild(plate)
        node.addChild(light)
        light.run(.repeatForever(.sequence([.scale(to: 1.4, duration: 0.4), .scale(to: 1, duration: 0.4)])))
    }

    override func update(_ g: GameScene) {
        guard alive, touchesPlayer(g, radius: 7) else { return }
        alive = false
        light.removeAllActions()
        light.setScale(1)
        light.fillColor = Theme.ninja
        plate.fillColor = Theme.accent
        g.activateExit()
    }
}

final class ExitDoor: Entity {
    private let frameNode = SKShapeNode(rectOf: CGSize(width: 20, height: 24))
    private let panel = SKShapeNode(rectOf: CGSize(width: 14, height: 20))
    private(set) var open = false

    override init(at p: CGPoint) {
        super.init(at: p)
        frameNode.fillColor = Theme.doorClosed
        frameNode.strokeColor = Theme.ninja
        frameNode.lineWidth = 1.5
        panel.fillColor = Theme.rgb(0x3E434D)
        panel.strokeColor = .clear
        panel.position = CGPoint(x: 0, y: -2)
        node.addChild(frameNode)
        node.addChild(panel)
    }

    func setOpen() {
        open = true
        panel.fillColor = Theme.accent
        frameNode.run(.repeatForever(.sequence([.scale(to: 1.08, duration: 0.35), .scale(to: 1, duration: 0.35)])))
    }

    override func update(_ g: GameScene) {
        guard open, touchesPlayer(g, radius: 8) else { return }
        g.levelComplete()
    }
}

final class Key: Entity {
    override init(at p: CGPoint) {
        super.init(at: p)
        let shape = SKShapeNode()
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: -7, y: -3, width: 6, height: 6))
        path.move(to: CGPoint(x: -1, y: 0)); path.addLine(to: CGPoint(x: 7, y: 0))
        path.move(to: CGPoint(x: 4, y: 0)); path.addLine(to: CGPoint(x: 4, y: -3))
        path.move(to: CGPoint(x: 6.5, y: 0)); path.addLine(to: CGPoint(x: 6.5, y: -3))
        shape.path = path
        shape.strokeColor = Theme.key
        shape.lineWidth = 2
        node.addChild(shape)
        node.run(.repeatForever(.sequence([.rotate(byAngle: 0.25, duration: 0.5), .rotate(byAngle: -0.25, duration: 0.5)])))
    }

    override func update(_ g: GameScene) {
        guard alive, touchesPlayer(g, radius: 7) else { return }
        alive = false
        node.removeAllActions()
        node.run(.sequence([.group([.scale(to: 2, duration: 0.25), .fadeOut(withDuration: 0.25)]), .removeFromParent()]))
        g.collectKey()
    }
}

final class Launchpad: Entity {
    private let plate = SKShapeNode(rectOf: CGSize(width: 18, height: 4), cornerRadius: 1)
    private var cooldown = 0
    private var floorY: CGFloat { pos.y - TS / 2 }

    override init(at p: CGPoint) {
        super.init(at: p)
        plate.fillColor = Theme.launchpad
        plate.strokeColor = Theme.ninja
        plate.lineWidth = 1
        plate.position = CGPoint(x: 0, y: -TS / 2 + 2)
        let arrow = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -4, y: -4)); path.addLine(to: CGPoint(x: 0, y: 0)); path.addLine(to: CGPoint(x: 4, y: -4))
        arrow.path = path
        arrow.strokeColor = Theme.launchpad
        arrow.lineWidth = 2
        arrow.position = CGPoint(x: 0, y: -2)
        arrow.run(.repeatForever(.sequence([.moveBy(x: 0, y: 3, duration: 0.4), .moveBy(x: 0, y: -3, duration: 0.4)])))
        node.addChild(arrow)
        node.addChild(plate)
    }

    override func update(_ g: GameScene) {
        if cooldown > 0 { cooldown -= 1; return }
        guard g.state == .playing else { return }
        let p = g.player
        if abs(p.pos.x - pos.x) < 14, p.pos.y - floorY < p.r + 8, p.pos.y > floorY, p.vel.y < 4 {
            p.launch(vy: 6)
            Sound.shared.play(.launchpad)
            cooldown = 20
            plate.run(.sequence([.scaleY(to: 2.5, duration: 0.05), .scaleY(to: 1, duration: 0.2)]))
            Haptics.light()
        }
    }
}

// MARK: - Enemies

/// Drone that moves cell to cell. Regular drones bounce back and forth;
/// chasers rush the ninja when they see it along a row or column.
final class Drone: Entity {
    private var dir: (x: Int, y: Int)
    private var cell: (x: Int, y: Int)
    private var target: CGPoint
    private let chaser: Bool
    private var chasing = false
    private let eye = SKShapeNode(circleOfRadius: 2.5)

    init(at p: CGPoint, dir: (Int, Int), chaser: Bool, map: LevelMap) {
        self.dir = dir
        self.chaser = chaser
        cell = map.cell(of: p)
        target = p
        super.init(at: p)
        let bodyNode = SKShapeNode(circleOfRadius: 9)
        bodyNode.fillColor = chaser ? Theme.chaser : Theme.drone
        bodyNode.strokeColor = Theme.ninja
        bodyNode.lineWidth = 1.5
        node.addChild(bodyNode)
        let ring = SKShapeNode(circleOfRadius: 5.5)
        ring.fillColor = Theme.lightText
        ring.strokeColor = .clear
        node.addChild(ring)
        eye.fillColor = Theme.ninja
        eye.strokeColor = .clear
        node.addChild(eye)
        if chaser {
            bodyNode.run(.repeatForever(.sequence([.scale(to: 1.08, duration: 0.3), .scale(to: 1, duration: 0.3)])))
        }
    }

    override func update(_ g: GameScene) {
        let speed: CGFloat = chasing ? 2.0 : 1.0
        let d = target - pos
        if d.length <= speed {
            pos = target
            chooseDirection(g)
            if dir.x != 0 || dir.y != 0 {
                cell = (cell.x + dir.x, cell.y + dir.y)
                target = CGPoint(x: (CGFloat(cell.x) + 0.5) * TS, y: (CGFloat(cell.y) + 0.5) * TS)
            }
        } else {
            pos += d.normalized * speed
        }
        node.position = pos
        eye.position = CGPoint(x: CGFloat(dir.x) * 2.5, y: CGFloat(dir.y) * 2.5)
        if touchesPlayer(g, radius: 8) {
            g.zap(at: g.player.pos)
            g.killPlayer()
        }
    }

    private func chooseDirection(_ g: GameScene) {
        let map = g.map
        chasing = false
        if chaser, g.state == .playing, let chase = sightOfPlayer(g) {
            dir = chase
            chasing = true
            return
        }
        let options = [dir, (-dir.x, -dir.y), (dir.y, -dir.x), (-dir.y, dir.x)]
        for o in options where o.0 != 0 || o.1 != 0 {
            if map.isOpenCell(cell.x + o.0, cell.y + o.1) {
                dir = o
                return
            }
        }
        dir = (0, 0)
    }

    private func sightOfPlayer(_ g: GameScene) -> (Int, Int)? {
        let pc = g.map.cell(of: g.player.pos)
        let dx = pc.x - cell.x, dy = pc.y - cell.y
        guard (dx == 0) != (dy == 0), abs(dx) + abs(dy) <= 12 else { return nil }
        let step = (dx.signum(), dy.signum())
        var c = cell
        while c.x != pc.x || c.y != pc.y {
            c = (c.x + step.0, c.y + step.1)
            if !g.map.isOpenCell(c.x, c.y) { return nil }
        }
        return step
    }
}

/// Gauss turret: locks on with a lagging aim, then fires an instant beam.
final class GaussTurret: Entity {
    private var aim = CGPoint.zero
    private var charge = 0
    private var cooldown = 0
    private let line = SKShapeNode()
    private let barrel = SKShapeNode(rectOf: CGSize(width: 10, height: 3), cornerRadius: 1)
    private let chargeTime = 60

    override init(at p: CGPoint) {
        super.init(at: p)
        line.strokeColor = Theme.beam
        line.lineWidth = 1
        line.zPosition = -1
        node.addChild(line)
        barrel.fillColor = Theme.ninja
        barrel.strokeColor = .clear
        barrel.position = .zero
        let base = SKShapeNode(circleOfRadius: 7)
        base.fillColor = Theme.turret
        base.strokeColor = Theme.ninja
        base.lineWidth = 1.5
        node.addChild(base)
        node.addChild(barrel)
        let core = SKShapeNode(circleOfRadius: 2.5)
        core.fillColor = Theme.beam
        core.strokeColor = .clear
        node.addChild(core)
    }

    override func update(_ g: GameScene) {
        if cooldown > 0 { cooldown -= 1; line.path = nil; return }
        let target = g.player.pos
        let canSee = g.state == .playing && g.map.lineOfSight(pos, target)
        if charge == 0 {
            guard canSee else { line.path = nil; return }
            aim = target
            Sound.shared.play(.lockOn)
        }
        if !canSee && charge > 0 {
            charge -= 2
            if charge <= 0 { charge = 0; line.path = nil; return }
        } else {
            charge += 1
            let d = target - aim
            aim += d.length > 2.0 ? d.normalized * 2.0 : d
        }
        let dir = (aim - pos).normalized
        barrel.position = dir * 6
        barrel.zRotation = atan2(dir.y, dir.x)

        if charge >= chargeTime {
            fire(g, dir: dir)
            return
        }
        let len = g.map.raycast(from: pos, dir: dir, maxDist: 900)
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: dir * len)
        line.path = path
        line.alpha = 0.25 + 0.6 * CGFloat(charge) / CGFloat(chargeTime)
        line.lineWidth = 0.5 + CGFloat(charge) / CGFloat(chargeTime)
    }

    private func fire(_ g: GameScene, dir: CGPoint) {
        Sound.shared.play(.gauss)
        charge = 0
        cooldown = 45
        line.path = nil
        let len = g.map.raycast(from: pos, dir: dir, maxDist: 900)
        let end = pos + dir * len
        let beam = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: pos)
        path.addLine(to: end)
        beam.path = path
        beam.strokeColor = Theme.beam
        beam.lineWidth = 3
        beam.glowWidth = 2
        g.fxLayer.addChild(beam)
        beam.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
        if g.state == .playing && distanceToSegment(g.player.pos, pos, end) < g.player.r + 1.5 {
            g.killPlayer()
        }
    }
}

final class RocketTurret: Entity {
    private var rocket: Rocket?
    private var cooldown = 60
    private let barrel = SKShapeNode(rectOf: CGSize(width: 12, height: 5), cornerRadius: 1.5)

    override init(at p: CGPoint) {
        super.init(at: p)
        let base = SKShapeNode(rectOf: CGSize(width: 16, height: 16), cornerRadius: 4)
        base.fillColor = Theme.turret
        base.strokeColor = Theme.ninja
        base.lineWidth = 1.5
        barrel.fillColor = Theme.ninja
        barrel.strokeColor = .clear
        node.addChild(base)
        node.addChild(barrel)
    }

    override func update(_ g: GameScene) {
        let dir = (g.player.pos - pos).normalized
        barrel.position = dir * 6
        barrel.zRotation = atan2(dir.y, dir.x)

        if let r = rocket {
            r.update(g)
            if !r.alive { rocket = nil; cooldown = 80 }
            return
        }
        if cooldown > 0 { cooldown -= 1; return }
        if g.state == .playing && g.map.lineOfSight(pos, g.player.pos) {
            let r = Rocket(at: pos + dir * 10, angle: atan2(dir.y, dir.x))
            g.fxLayer.addChild(r.node)
            rocket = r
            Sound.shared.play(.rocket)
        }
    }
}

final class Rocket: Entity {
    private var angle: CGFloat
    private var speed: CGFloat = 0.6
    private var t = 0

    init(at p: CGPoint, angle: CGFloat) {
        self.angle = angle
        super.init(at: p)
        let body = SKShapeNode(rectOf: CGSize(width: 9, height: 4), cornerRadius: 2)
        body.fillColor = Theme.ninja
        body.strokeColor = .clear
        let flame = SKShapeNode(circleOfRadius: 2)
        flame.fillColor = Theme.launchpad
        flame.strokeColor = .clear
        flame.position = CGPoint(x: -5, y: 0)
        flame.run(.repeatForever(.sequence([.scale(to: 1.5, duration: 0.05), .scale(to: 0.8, duration: 0.05)])))
        node.addChild(flame)
        node.addChild(body)
        node.zRotation = angle
    }

    override func update(_ g: GameScene) {
        guard alive else { return }
        t += 1
        let want = atan2(g.player.pos.y - pos.y, g.player.pos.x - pos.x)
        var delta = want - angle
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        if g.state == .playing { angle += clamp(delta, -0.04, 0.04) }
        speed = min(speed + 0.04, 2.7)
        pos += CGPoint(x: cos(angle), y: sin(angle)) * speed
        node.position = pos
        node.zRotation = angle

        if t % 4 == 0 {
            let puff = SKShapeNode(circleOfRadius: 2.5)
            puff.fillColor = Theme.rgb(0x9097A3, 0.6)
            puff.strokeColor = .clear
            puff.position = pos - CGPoint(x: cos(angle), y: sin(angle)) * 6
            g.fxLayer.addChild(puff)
            puff.run(.sequence([.group([.scale(to: 2, duration: 0.5), .fadeOut(withDuration: 0.5)]), .removeFromParent()]))
        }

        if touchesPlayer(g, radius: 4) {
            explode(g)
            g.killPlayer()
        } else if g.map.isSolid(pos) || t > 60 * 12 {
            explode(g)
        }
    }

    private func explode(_ g: GameScene) {
        alive = false
        g.explosion(at: pos, radius: 18)
        node.removeFromParent()
    }
}
