import SpriteKit

final class MenuScene: BaseScene {
    private let title = makeLabel("NINJA RUN", size: 64, font: Theme.logoFont, color: Theme.ninja)
    private let subtitle = makeLabel(L.subtitle, size: 16, font: Theme.uiFont, color: Theme.text)
    private var play: ButtonNode!
    private var soundButton: ButtonNode!
    private var langButton: ButtonNode!
    private var picker: SKNode?
    private let ground = SKShapeNode()
    private let ninja = NinjaNode()
    private var nx: CGFloat = 60
    private var vx: CGFloat = 3
    private var phase: CGFloat = 0
    private var t: CGFloat = 0

    // Trick show: the ninja runs, hops and flips on its own.
    private enum Trick: CaseIterable { case hop, frontFlip, backFlip, doubleFlip, spin }
    private let scale: CGFloat = 2.2
    private let gravity: CGFloat = 0.42
    private var groundY: CGFloat = 0
    private var height: CGFloat = 0        // above the ground
    private var vy: CGFloat = 0
    private var airFrames: CGFloat = 0
    private var airTotal: CGFloat = 1
    private var turns: CGFloat = 0         // full rotations, + = forward
    private var spinning = false
    private var nextTrick = 70

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = Theme.levelBG
        addChild(title)
        addChild(subtitle)
        play = ButtonNode(text: L.play, size: CGSize(width: 220, height: 54), fontSize: 24, color: Theme.accent) { [weak self] in
            guard let self else { return }
            self.go(to: LevelSelectScene(size: self.size))
        }
        addChild(play)
        soundButton = ButtonNode(text: "", size: CGSize(width: 160, height: 38), fontSize: 16) { [weak self] in
            Sound.shared.enabled.toggle()
            self?.updateSoundLabel()
        }
        updateSoundLabel()
        addChild(soundButton)
        langButton = ButtonNode(text: "\(L.language): \(Lang.current.nativeName)", size: CGSize(width: 200, height: 38),
                                fontSize: 16) { [weak self] in self?.showLanguagePicker() }
        addChild(langButton)
        ground.fillColor = Theme.tile
        ground.strokeColor = .clear
        addChild(ground)
        ninja.setScale(2.2)
        addChild(ninja)
        built = true
        layoutScene()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutScene() {
        guard built else { return }
        let W = size.width, H = size.height
        title.position = CGPoint(x: W / 2, y: H * 0.76)
        subtitle.position = CGPoint(x: W / 2, y: H * 0.76 - 48)
        play.position = CGPoint(x: W / 2, y: H * 0.50)
        soundButton.position = CGPoint(x: W / 2 - 92, y: H * 0.50 - 54)
        langButton.position = CGPoint(x: W / 2 + 112, y: H * 0.50 - 54)
        picker?.position = CGPoint(x: W / 2, y: H / 2)
        let gh = insets.bottom + 40
        ground.path = CGPath(rect: CGRect(x: 0, y: 0, width: W, height: gh), transform: nil)
        groundY = gh + 10 * scale
        ninja.position.y = groundY + height
    }

    private func showLanguagePicker() {
        guard picker == nil else { return }
        let o = SKNode()
        o.zPosition = 100
        let dim = SKShapeNode(rectOf: CGSize(width: 4000, height: 4000))
        dim.fillColor = Theme.rgb(0x000000, 0.45)
        dim.strokeColor = .clear
        o.addChild(dim)
        let cols = 4
        let cellW: CGFloat = 150, cellH: CGFloat = 44, gap: CGFloat = 12
        let gridW = CGFloat(cols) * cellW + CGFloat(cols - 1) * gap
        let panel = SKShapeNode(rectOf: CGSize(width: gridW + 40, height: 190), cornerRadius: 18)
        panel.fillColor = Theme.levelBG
        panel.strokeColor = .clear
        o.addChild(panel)
        let header = makeLabel(L.language, size: 24, font: Theme.titleFont)
        header.position = CGPoint(x: 0, y: 60)
        o.addChild(header)
        for (i, lang) in Lang.allCases.enumerated() {
            let selected = lang == Lang.current
            let b = ButtonNode(text: lang.nativeName, size: CGSize(width: cellW, height: cellH), fontSize: 17,
                               color: selected ? Theme.accent : Theme.button) { [weak self] in
                guard let self else { return }
                Lang.current = lang
                self.go(to: MenuScene(size: self.size), fade: false)
            }
            // Each button shows its language in its own script.
            b.label.fontName = lang == .zh ? "PingFangSC-Semibold" : "AvenirNext-DemiBold"
            let row = i / cols, col = i % cols
            let inRow = row == 0 ? cols : Lang.allCases.count - cols
            let rowW = CGFloat(inRow) * cellW + CGFloat(inRow - 1) * gap
            b.position = CGPoint(x: -rowW / 2 + cellW / 2 + CGFloat(col) * (cellW + gap),
                                 y: 10 - CGFloat(row) * (cellH + gap))
            o.addChild(b)
        }
        let s = min(1, (size.width - insets.left - insets.right - 24) / (gridW + 40))
        o.setScale(s)
        o.position = CGPoint(x: size.width / 2, y: size.height / 2)
        picker = o
        addChild(o)
    }

    override func gameTouchBegan(_ t: UITouch) {
        // Tapping outside the language buttons closes the picker.
        picker?.removeFromParent()
        picker = nil
    }

    private func updateSoundLabel() {
        soundButton.label.text = Sound.shared.enabled ? L.soundOn : L.soundOff
    }

    override func update(_ currentTime: TimeInterval) {
        t += 1 / 60
        let W = size.width
        let airborne = height > 0 || vy > 0
        nx += vx

        // At the screen edge: either a wall kick with a back flip or a quick turn.
        if (nx > W - 40 && vx > 0) || (nx < 40 && vx < 0) {
            vx = -vx
            if !airborne && Bool.random() {
                jump(vy: 7.5, turns: -1)
            }
        }

        if airborne {
            vy -= gravity
            height += vy
            airFrames += 1
            if height <= 0 { land() }
        } else {
            phase += abs(vx) * 0.22
            nextTrick -= 1
            if nextTrick <= 0 { startRandomTrick() }
        }

        let facing: CGFloat = vx > 0 ? 1 : -1
        let k = min(airFrames / airTotal, 1)
        let eased = k * k * (3 - 2 * k)
        ninja.zRotation = height > 0 ? -facing * turns * 2 * .pi * eased : 0
        let spinFacing = spinning && height > 0 ? (Int(airFrames / 5) % 2 == 0 ? facing : -facing) : facing
        ninja.position = CGPoint(x: nx, y: groundY + height)
        ninja.pose(vel: CGPoint(x: vx, y: height > 0 ? vy / scale * 2 : 0), grounded: height <= 0,
                   wallSliding: false, wallSide: 0, facing: spinFacing, phase: phase, time: t)
    }

    private func startRandomTrick() {
        switch Trick.allCases.randomElement()! {
        case .hop: jump(vy: 5, turns: 0)
        case .frontFlip: jump(vy: 7.5, turns: 1)
        case .backFlip: jump(vy: 7.5, turns: -1)
        case .doubleFlip: jump(vy: 9.5, turns: 2)
        case .spin: jump(vy: 7, turns: 0, spin: true)
        }
        nextTrick = Int.random(in: 45...130)
    }

    private func jump(vy: CGFloat, turns: CGFloat, spin: Bool = false) {
        self.vy = vy
        height = 0.01
        airFrames = 0
        airTotal = 2 * vy / gravity
        self.turns = turns
        spinning = spin
        dust()
    }

    private func land() {
        height = 0
        vy = 0
        turns = 0
        spinning = false
        dust()
    }

    private func dust() {
        for i in 0..<5 {
            let p = SKShapeNode(circleOfRadius: 3)
            p.fillColor = Theme.rgb(0x6B7280, 0.6)
            p.strokeColor = .clear
            p.position = CGPoint(x: nx + CGFloat(i - 2) * 6, y: groundY - 10 * scale + 3)
            addChild(p)
            p.run(.sequence([.group([.moveBy(x: CGFloat(i - 2) * 10, y: 6, duration: 0.35),
                                     .fadeOut(withDuration: 0.35)]), .removeFromParent()]))
        }
    }
}

final class LevelSelectScene: BaseScene {
    private let header = makeLabel(L.levels, size: 30, font: Theme.titleFont, color: Theme.ninja)
    private var back: ButtonNode!
    private var cells: [ButtonNode] = []

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = Theme.levelBG
        addChild(header)
        back = ButtonNode(text: L.back, size: CGSize(width: 110, height: 36), fontSize: 16) { [weak self] in
            guard let self else { return }
            self.go(to: MenuScene(size: self.size))
        }
        addChild(back)

        let unlocked = Progress.unlocked
        for (i, def) in Levels.all.enumerated() {
            let open = i < unlocked
            let done = Progress.best(i) != nil
            let color = done ? Theme.accent : (open ? Theme.button : Theme.switchOff)
            let b = ButtonNode(text: "", size: CGSize(width: 150, height: 74), color: color) { [weak self] in
                guard let self, open else { return }
                self.go(to: GameScene(size: self.size, level: i))
            }
            b.label.text = "\(i + 1)"
            b.label.fontName = Theme.titleFont
            b.label.fontSize = 24
            b.label.position = CGPoint(x: 0, y: 12)
            let name = makeLabel(L.levelNames[i], size: 12, font: Theme.uiFont, color: Theme.lightText)
            name.position = CGPoint(x: 0, y: -10)
            b.addChild(name)
            let best = makeLabel(Progress.best(i).map { String(format: "★ %.1f", $0) } ?? " ", size: 11,
                                 font: Theme.monoFont, color: Theme.lightText)
            best.position = CGPoint(x: 0, y: -26)
            b.addChild(best)
            b.isEnabled = open
            if !open { b.alpha = 0.6 }
            cells.append(b)
            addChild(b)
        }
        built = true
        layoutScene()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutScene() {
        guard built else { return }
        let W = size.width, H = size.height
        let topY = H - insets.top - 34
        header.position = CGPoint(x: W / 2, y: topY)
        back.position = CGPoint(x: max(insets.left, 16) + 65, y: topY)

        let cols = 4, rows = (cells.count + cols - 1) / cols
        let cellW: CGFloat = 150, cellH: CGFloat = 74, gap: CGFloat = 14
        let gridW = CGFloat(cols) * cellW + CGFloat(cols - 1) * gap
        let gridH = CGFloat(rows) * cellH + CGFloat(rows - 1) * gap
        let availW = W - insets.left - insets.right - 32
        let availH = topY - 30 - insets.bottom - 12
        let s = min(1, availW / gridW, availH / gridH)
        let originX = W / 2 - gridW * s / 2 + cellW * s / 2
        let originY = (topY - 30 + insets.bottom + 12) / 2 + gridH * s / 2 - cellH * s / 2
        for (i, b) in cells.enumerated() {
            let c = i % cols, r = i / cols
            b.setScale(s)
            b.position = CGPoint(x: originX + CGFloat(c) * (cellW + gap) * s, y: originY - CGFloat(r) * (cellH + gap) * s)
        }
    }
}
