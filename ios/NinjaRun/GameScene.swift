import SpriteKit
import GameController

final class GameScene: BaseScene {
    enum State { case ready, playing, dead, won, paused }

    let index: Int
    let def: LevelDef
    let map: LevelMap
    private(set) var player: Player
    private(set) var state: State = .ready

    let world = SKNode()
    let fxLayer = SKNode()
    private let entityLayer = SKNode()
    private var entities: [Entity] = []
    private var exitDoor: ExitDoor?
    private var doorNodes: [SKNode] = []
    private var keysLeft = 0

    private let startTime: Double = 90
    private var timeLeft: Double = 90
    private var goldCount = 0
    private var goldTotal = 0
    private var frameCount = 0
    private var deadFrames = 0
    private var stateBeforePause: State = .ready

    // HUD
    private let titleLabel = makeLabel("", size: 15, font: Theme.uiFont, color: Theme.lightText)
    private let timeLabel = makeLabel("", size: 14, font: Theme.monoFont, color: Theme.lightText)
    private let goldLabel = makeLabel("", size: 14, font: Theme.monoFont, color: Theme.gold)
    private let barBG = SKShapeNode()
    private let barFill = SKShapeNode()
    private let barWidth: CGFloat = 220
    private var pauseButton: ButtonNode!
    private var restartButton: ButtonNode!
    private let hintLabel = SKLabelNode()
    private var overlay: SKNode?

    // Controls
    private enum Role { case pad, jump }
    private var touchRoles: [UITouch: Role] = [:]
    private var padDx: [UITouch: Int] = [:]
    private var jumpEdge = false
    private var keyJumpWasDown = false
    private let leftBtn = ControlButton(arrow: .left, radius: 34)
    private let rightBtn = ControlButton(arrow: .right, radius: 34)
    private let jumpBtn = ControlButton(arrow: .up, radius: 44)
    private var padCenter = CGPoint.zero

    private var lastUpdate: TimeInterval?
    private var accumulator: TimeInterval = 0
    private var debris: [Debris] = []

    init(size: CGSize, level: Int) {
        index = level
        def = Levels.all[level]
        map = LevelMap(map: def.map)
        let start = map.spawns.first { $0.kind == "P" }?.center ?? CGPoint(x: 48, y: 48)
        player = Player(at: start)
        super.init(size: size)
        backgroundColor = Theme.screen
        buildWorld()
        buildHUD()
        built = true
        layoutScene()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Building

    private func buildWorld() {
        addChild(world)
        let bg = SKShapeNode(rect: CGRect(origin: .zero, size: map.worldSize))
        bg.fillColor = Theme.levelBG
        bg.strokeColor = .clear
        world.addChild(bg)

        let tiles = SKShapeNode(path: map.staticTilesPath())
        tiles.fillColor = Theme.tile
        tiles.strokeColor = .clear
        tiles.isAntialiased = false
        world.addChild(tiles)

        for y in 0..<ROWS {
            for x in 0..<COLS where map.tiles[y][x] == .door {
                let d = SKShapeNode(rect: CGRect(x: CGFloat(x) * TS + 3, y: CGFloat(y) * TS, width: TS - 6, height: TS))
                d.fillColor = Theme.wood
                d.strokeColor = Theme.ninja
                d.lineWidth = 1
                world.addChild(d)
                doorNodes.append(d)
            }
        }

        world.addChild(entityLayer)
        for s in map.spawns {
            let c = s.center
            var e: Entity?
            switch s.kind {
            case "G": e = Gold(at: c); goldTotal += 1
            case "M": e = Mine(at: c)
            case "S": e = ExitSwitch(at: c)
            case "E": let d = ExitDoor(at: c); exitDoor = d; e = d
            case "k": e = Key(at: c); keysLeft += 1
            case "^": e = Launchpad(at: c)
            case "e": e = Drone(at: c, dir: (1, 0), chaser: false, map: map)
            case "w": e = Drone(at: c, dir: (-1, 0), chaser: false, map: map)
            case "n": e = Drone(at: c, dir: (0, 1), chaser: false, map: map)
            case "s": e = Drone(at: c, dir: (0, -1), chaser: false, map: map)
            case "c": e = Drone(at: c, dir: (1, 0), chaser: true, map: map)
            case "T": e = GaussTurret(at: c)
            case "r": e = RocketTurret(at: c)
            default: break
            }
            if let e {
                entities.append(e)
                entityLayer.addChild(e.node)
            }
        }
        world.addChild(player.node)
        world.addChild(fxLayer)
        player.syncNode(time: 0)
    }

    private func buildHUD() {
        titleLabel.text = "\(index + 1). \(L.levelNames[index])"
        titleLabel.horizontalAlignmentMode = .left
        addChild(titleLabel)

        barBG.path = CGPath(roundedRect: CGRect(x: 0, y: -5, width: barWidth, height: 10), cornerWidth: 5, cornerHeight: 5, transform: nil)
        barBG.fillColor = Theme.rgb(0x000000, 0.25)
        barBG.strokeColor = .clear
        addChild(barBG)
        barFill.fillColor = Theme.gold
        barFill.strokeColor = .clear
        barBG.addChild(barFill)
        addChild(timeLabel)
        goldLabel.horizontalAlignmentMode = .right
        addChild(goldLabel)

        pauseButton = ButtonNode(text: "II", size: CGSize(width: 44, height: 30), fontSize: 15) { [weak self] in self?.pause() }
        restartButton = ButtonNode(text: "↻", size: CGSize(width: 44, height: 30), fontSize: 18) { [weak self] in self?.restart() }
        addChild(pauseButton)
        addChild(restartButton)

        for b in [leftBtn, rightBtn, jumpBtn] { addChild(b) }
        #if DEBUG
        // Screenshot helper: launch with `-hideControls YES` for clean level shots.
        if UserDefaults.standard.bool(forKey: "hideControls") {
            for b in [leftBtn, rightBtn, jumpBtn] { b.isHidden = true }
        }
        #endif

        if index < L.hints.count {
            let hint = L.hints[index]
            hintLabel.text = hint
            hintLabel.numberOfLines = 0
            hintLabel.preferredMaxLayoutWidth = 520
            hintLabel.fontName = Theme.uiFont
            hintLabel.fontSize = 14
            hintLabel.fontColor = Theme.text
            hintLabel.verticalAlignmentMode = .top
            hintLabel.horizontalAlignmentMode = .center
            hintLabel.zPosition = 5
            world.addChild(hintLabel)
        }
        updateHUD()
    }

    override func layoutScene() {
        guard built else { return }
        let W = size.width, H = size.height
        let ins = insets
        let hudH: CGFloat = 36
        let top = H - ins.top - hudH
        let bottom = ins.bottom + 6
        let availH = top - bottom
        let ws = map.worldSize
        let s = min(availH / ws.height, (W - ins.left - ins.right - 8) / ws.width)
        world.setScale(s)
        let levelX = (W - ws.width * s) / 2
        world.position = CGPoint(x: levelX, y: bottom + (availH - ws.height * s) / 2)
        hintLabel.position = CGPoint(x: ws.width / 2, y: ws.height - TS * 1.4)
        hintLabel.setScale(0.75 / max(s, 0.5))

        let hudY = H - ins.top - hudH / 2
        let left = max(ins.left, 12) + 4
        let right = W - max(ins.right, 12) - 4
        pauseButton.position = CGPoint(x: left + 22, y: hudY)
        titleLabel.position = CGPoint(x: left + 54, y: hudY)
        restartButton.position = CGPoint(x: right - 22, y: hudY)
        goldLabel.position = CGPoint(x: right - 56, y: hudY)
        barBG.position = CGPoint(x: W / 2 - barWidth / 2 + 40, y: hudY)
        timeLabel.position = CGPoint(x: W / 2 - barWidth / 2 + 4, y: hudY)

        // Controls live in the side margins when there is room, otherwise overlap the level.
        let sideSpace = levelX - ins.left
        let padX = sideSpace > 170 ? ins.left + sideSpace / 2 : left + 80
        padCenter = CGPoint(x: padX, y: bottom + 66)
        leftBtn.position = CGPoint(x: padX - 42, y: padCenter.y)
        rightBtn.position = CGPoint(x: padX + 42, y: padCenter.y)
        let rightSpace = W - ins.right - (levelX + ws.width * s)
        let jx = rightSpace > 130 ? W - ins.right - rightSpace / 2 : right - 60
        jumpBtn.position = CGPoint(x: jx, y: bottom + 70)

        if let overlay { layoutOverlay(overlay) }
    }

    // MARK: - Game events (called by entities)

    func collectGold() {
        goldCount += 1
        timeLeft += 2
        Sound.shared.play(.gold)
        Haptics.light()
    }

    func activateExit() {
        exitDoor?.setOpen()
        Sound.shared.play(.switchOn)
        run(.wait(forDuration: 0.15)) { Sound.shared.play(.doorOpen) }
        Haptics.light()
    }

    func collectKey() {
        keysLeft -= 1
        Sound.shared.play(.key)
        if keysLeft <= 0 {
            map.doorsOpen = true
            for d in doorNodes {
                d.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
            }
        }
        Haptics.light()
    }

    func killPlayer() {
        guard state == .playing else { return }
        state = .dead
        deadFrames = 0
        player.node.isHidden = true
        spawnDebris()
        Sound.shared.play(.death)
        Haptics.heavy()
    }

    func levelComplete() {
        guard state == .playing else { return }
        state = .won
        Progress.record(level: index, timeLeft: timeLeft)
        Haptics.success()
        Sound.shared.play(.win)
        player.node.run(.sequence([.scale(to: 0.1, duration: 0.25), .hide()]))
        showWinOverlay()
    }

    func explosion(at p: CGPoint, radius: CGFloat) {
        Sound.shared.play(.explosion)
        let ring = SKShapeNode(circleOfRadius: radius)
        ring.position = p
        ring.fillColor = Theme.rgb(0xFF8A3D, 0.8)
        ring.strokeColor = Theme.mine
        ring.lineWidth = 2
        ring.setScale(0.2)
        fxLayer.addChild(ring)
        ring.run(.sequence([.group([.scale(to: 1, duration: 0.18), .fadeOut(withDuration: 0.35)]), .removeFromParent()]))
    }

    func zap(at p: CGPoint) {
        Sound.shared.play(.zap)
        let path = CGMutablePath()
        var cur = p + CGPoint(x: -14, y: 10)
        path.move(to: cur)
        for _ in 0..<6 {
            cur = cur + CGPoint(x: 5, y: CGFloat.random(in: -8...8))
            path.addLine(to: cur)
        }
        let bolt = SKShapeNode(path: path)
        bolt.strokeColor = Theme.rgb(0x7FD3FF)
        bolt.lineWidth = 2
        bolt.glowWidth = 2
        fxLayer.addChild(bolt)
        bolt.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
    }

    // MARK: - Loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate.map { min(currentTime - $0, 0.1) } ?? 1.0 / 60
        lastUpdate = currentTime
        guard state != .paused else { return }
        accumulator += dt
        var steps = 0
        while accumulator >= 1.0 / 60 && steps < 5 {
            fixedStep()
            accumulator -= 1.0 / 60
            steps += 1
        }
        if steps == 5 { accumulator = 0 }
        player.syncNode(time: CGFloat(frameCount) / 60)
        updateHUD()
    }

    private func fixedStep() {
        frameCount += 1
        let inp = readInput()

        switch state {
        case .ready:
            guard inp.dx != 0 || inp.jumpPressed else { return }
            state = .playing
            hintLabel.run(.sequence([.wait(forDuration: 2.5), .fadeOut(withDuration: 0.6)]))
            stepPlaying(inp)
        case .playing:
            stepPlaying(inp)
        case .dead:
            deadFrames += 1
            stepDebris()
            for e in entities { e.update(self) }
            if (deadFrames > 25 && inp.jumpPressed) || deadFrames > 80 { restart() }
        case .won, .paused:
            break
        }
    }

    private func stepPlaying(_ inp: InputState) {
        timeLeft -= 1.0 / 60
        if timeLeft <= 0 {
            timeLeft = 0
            killPlayer()
            return
        }
        if player.step(inp, map: map) {
            killPlayer()
            return
        }
        if player.didJump {
            jumpDust()
            Sound.shared.play(player.didWallJump ? .wallJump : .jump)
        } else if player.landImpact > 1.2 {
            Sound.shared.play(.land)
        }
        for e in entities {
            e.update(self)
            if state != .playing && state != .dead { break }
        }
    }

    private func readInput() -> InputState {
        var inp = InputState()
        let touchDx = padDx.values.reduce(0, +)
        inp.dx = clamp(touchDx, -1, 1)
        inp.jumpHeld = touchRoles.values.contains(.jump)
        inp.jumpPressed = jumpEdge
        jumpEdge = false

        if let kb = GCKeyboard.coalesced?.keyboardInput {
            let l = kb.button(forKeyCode: .leftArrow)?.isPressed == true || kb.button(forKeyCode: .keyA)?.isPressed == true
            let r = kb.button(forKeyCode: .rightArrow)?.isPressed == true || kb.button(forKeyCode: .keyD)?.isPressed == true
            if inp.dx == 0 { inp.dx = (r ? 1 : 0) - (l ? 1 : 0) }
            let j = kb.button(forKeyCode: .spacebar)?.isPressed == true
                || kb.button(forKeyCode: .upArrow)?.isPressed == true
                || kb.button(forKeyCode: .keyW)?.isPressed == true
                || kb.button(forKeyCode: .keyZ)?.isPressed == true
            if j && !keyJumpWasDown { inp.jumpPressed = true }
            keyJumpWasDown = j
            inp.jumpHeld = inp.jumpHeld || j
        }
        leftBtn.setActive(inp.dx < 0)
        rightBtn.setActive(inp.dx > 0)
        jumpBtn.setActive(inp.jumpHeld)
        return inp
    }

    private func updateHUD() {
        timeLabel.text = String(format: "%5.1f", timeLeft)
        goldLabel.text = "■ \(goldCount)/\(goldTotal)"
        let frac = CGFloat(clamp(timeLeft / startTime, 0, 1))
        barFill.path = CGPath(roundedRect: CGRect(x: 0, y: -5, width: max(barWidth * frac, 0.1), height: 10),
                              cornerWidth: min(5, barWidth * frac / 2), cornerHeight: 5, transform: nil)
        barFill.fillColor = timeLeft < 15 ? Theme.mine : Theme.gold
    }

    // MARK: - Effects

    private func jumpDust() {
        for i in 0..<4 {
            let p = SKShapeNode(circleOfRadius: 1.6)
            p.fillColor = Theme.rgb(0x6B7280, 0.7)
            p.strokeColor = .clear
            p.position = player.pos + CGPoint(x: CGFloat(i - 2) * 3, y: -player.r)
            fxLayer.addChild(p)
            p.run(.sequence([.group([.moveBy(x: CGFloat(i - 2) * 5, y: 3, duration: 0.3), .fadeOut(withDuration: 0.3)]), .removeFromParent()]))
        }
    }

    private struct Debris {
        let node: SKShapeNode
        var pos: CGPoint
        var vel: CGPoint
        var spin: CGFloat
    }

    private func spawnDebris() {
        let base = player.vel
        let parts: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 0, y: -4), CGPoint(x: 0, y: 4)),
            (CGPoint(x: -3, y: -4), CGPoint(x: 3, y: 4)),
            (CGPoint(x: -3, y: -4), CGPoint(x: 3, y: 4)),
            (CGPoint(x: -3, y: -3), CGPoint(x: 3, y: 3)),
            (CGPoint(x: -3, y: -3), CGPoint(x: 3, y: 3)),
        ]
        var shapes: [SKShapeNode] = parts.map { a, b in
            let p = CGMutablePath(); p.move(to: a); p.addLine(to: b)
            let n = SKShapeNode(path: p)
            n.strokeColor = Theme.ninja
            n.lineWidth = 2
            n.lineCap = .round
            return n
        }
        let head = SKShapeNode(circleOfRadius: 3.6)
        head.fillColor = Theme.ninja
        head.strokeColor = .clear
        shapes.append(head)
        let scarf = SKShapeNode(rectOf: CGSize(width: 7, height: 1.6))
        scarf.fillColor = Theme.scarf
        scarf.strokeColor = .clear
        shapes.append(scarf)
        for n in shapes {
            fxLayer.addChild(n)
            let v = base * 0.6 + CGPoint(x: CGFloat.random(in: -2.2...2.2), y: CGFloat.random(in: 0.5...3.2))
            debris.append(Debris(node: n, pos: player.pos + CGPoint(x: CGFloat.random(in: -4...4), y: CGFloat.random(in: -6...6)),
                                 vel: v, spin: CGFloat.random(in: -0.3...0.3)))
        }
    }

    private func stepDebris() {
        for i in debris.indices {
            var d = debris[i]
            d.vel.y -= 0.12
            d.vel = d.vel * 0.99
            let next = d.pos + d.vel
            if map.isSolid(CGPoint(x: next.x, y: d.pos.y)) { d.vel.x *= -0.4; d.spin *= 0.5 }
            if map.isSolid(CGPoint(x: d.pos.x, y: next.y)) { d.vel.y *= -0.35; d.vel.x *= 0.7; d.spin *= 0.5 }
            d.pos = d.pos + d.vel
            d.node.position = d.pos
            d.node.zRotation += d.spin
            debris[i] = d
        }
    }

    // MARK: - Touch controls

    override func gameTouchBegan(_ t: UITouch) {
        guard overlay == nil else { return }
        let p = t.location(in: self)
        if p.x < size.width / 2 {
            touchRoles[t] = .pad
            padDx[t] = p.x < padCenter.x ? -1 : 1
        } else {
            touchRoles[t] = .jump
            jumpEdge = true
        }
    }

    override func gameTouchMoved(_ t: UITouch) {
        guard touchRoles[t] == .pad else { return }
        let p = t.location(in: self)
        padDx[t] = p.x < padCenter.x ? -1 : 1
    }

    override func gameTouchEnded(_ t: UITouch) {
        touchRoles[t] = nil
        padDx[t] = nil
    }

    // MARK: - Flow & overlays

    private func restart() {
        let s = GameScene(size: size, level: index)
        go(to: s, fade: false)
    }

    private func pause() {
        guard state != .won, overlay == nil else { return }
        stateBeforePause = state
        state = .paused
        clearTouches()
        showPauseMenu()
    }

    private func showPauseMenu() {
        showOverlay(title: L.pause, subtitle: nil, buttons: [
            (L.resume, { [weak self] in self?.resume() }),
            (L.restart, { [weak self] in self?.restart() }),
            (Sound.shared.enabled ? L.soundOn : L.soundOff, { [weak self] in
                Sound.shared.enabled.toggle()
                self?.overlay?.removeFromParent()
                self?.overlay = nil
                self?.showPauseMenu()
            }),
            (L.levels, { [weak self] in self?.goToLevels() }),
        ])
    }

    private func resume() {
        overlay?.removeFromParent()
        overlay = nil
        state = stateBeforePause
        lastUpdate = nil
    }

    private func goToLevels() {
        go(to: LevelSelectScene(size: size))
    }

    private func showWinOverlay() {
        clearTouches()
        let best = Progress.best(index) ?? timeLeft
        let sub = String(format: L.winStats, timeLeft, best, goldCount, goldTotal)
        var buttons: [(String, () -> Void)] = []
        if index + 1 < Levels.all.count {
            buttons.append((L.next, { [weak self] in
                guard let self else { return }
                self.go(to: GameScene(size: self.size, level: self.index + 1))
            }))
        }
        buttons.append((L.again, { [weak self] in self?.restart() }))
        buttons.append((L.levels, { [weak self] in self?.goToLevels() }))
        let title = index + 1 < Levels.all.count ? L.levelComplete : L.gameComplete
        run(.wait(forDuration: 0.35)) { [weak self] in
            self?.showOverlay(title: title, subtitle: sub, buttons: buttons)
        }
    }

    private func clearTouches() {
        touchRoles.removeAll()
        padDx.removeAll()
        jumpEdge = false
    }

    private func showOverlay(title: String, subtitle: String?, buttons: [(String, () -> Void)]) {
        let o = SKNode()
        o.zPosition = 100
        let dim = SKShapeNode(rectOf: CGSize(width: 4000, height: 4000))
        dim.fillColor = Theme.rgb(0x000000, 0.45)
        dim.strokeColor = .clear
        dim.name = "dim"
        o.addChild(dim)
        let panel = SKShapeNode(rectOf: CGSize(width: 380, height: 120 + CGFloat(buttons.count) * 52), cornerRadius: 18)
        panel.fillColor = Theme.levelBG
        panel.strokeColor = .clear
        panel.name = "panel"
        o.addChild(panel)
        let content = SKNode()
        content.name = "content"
        o.addChild(content)
        let totalH = 120 + CGFloat(buttons.count) * 52
        let t = makeLabel(title, size: 28, font: Theme.titleFont)
        t.position = CGPoint(x: 0, y: totalH / 2 - 36)
        content.addChild(t)
        if let subtitle {
            let s = makeLabel(subtitle, size: 13, font: Theme.uiFont, color: Theme.text)
            s.position = CGPoint(x: 0, y: totalH / 2 - 66)
            content.addChild(s)
        }
        for (i, b) in buttons.enumerated() {
            let btn = ButtonNode(text: b.0, size: CGSize(width: 240, height: 42), fontSize: 18,
                                 color: i == 0 ? Theme.accent : Theme.button, action: b.1)
            btn.position = CGPoint(x: 0, y: totalH / 2 - 112 - CGFloat(i) * 52)
            content.addChild(btn)
        }
        overlay = o
        addChild(o)
        layoutOverlay(o)
        o.alpha = 0
        o.run(.fadeIn(withDuration: 0.2))
    }

    private func layoutOverlay(_ o: SKNode) {
        o.position = CGPoint(x: size.width / 2, y: size.height / 2)
        guard let panel = o.childNode(withName: "panel") else { return }
        let h = panel.frame.height
        let s = min(1, (size.height - insets.top - insets.bottom - 20) / h)
        panel.setScale(s)
        o.childNode(withName: "content")?.setScale(s)
    }
}

/// Round on-screen control with a symbol.
final class ControlButton: SKNode {
    private let circle: SKShapeNode
    enum Arrow: CGFloat { case right = 0, up = 1, left = 2 }

    init(arrow: Arrow, radius: CGFloat) {
        circle = SKShapeNode(circleOfRadius: radius)
        super.init()
        circle.fillColor = Theme.rgb(0xFFFFFF, 0.18)
        circle.strokeColor = Theme.rgb(0xFFFFFF, 0.45)
        circle.lineWidth = 2
        addChild(circle)
        let a = radius * 0.32
        let tri = SKShapeNode()
        let path = CGMutablePath()
        path.addLines(between: [CGPoint(x: a, y: 0), CGPoint(x: -a * 0.6, y: a), CGPoint(x: -a * 0.6, y: -a)])
        path.closeSubpath()
        tri.path = path
        tri.fillColor = Theme.rgb(0xFFFFFF, 0.85)
        tri.strokeColor = .clear
        tri.zRotation = arrow.rawValue * .pi / 2
        addChild(tri)
        zPosition = 50
    }

    required init?(coder: NSCoder) { fatalError() }

    func setActive(_ on: Bool) {
        circle.fillColor = Theme.rgb(0xFFFFFF, on ? 0.45 : 0.18)
    }
}
