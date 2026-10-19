import SpriteKit
import UIKit

enum Theme {
    static func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: a)
    }
    static let screen = rgb(0x8E939E)
    static let levelBG = rgb(0xD3D6DD)
    static let tile = rgb(0x474C59)
    static let tileEdge = rgb(0x5C6271)
    static let text = rgb(0x22252D)
    static let lightText = rgb(0xF4F5F7)
    static let ninja = rgb(0x121318)
    static let scarf = rgb(0xE0393E)
    static let gold = rgb(0xF2C230)
    static let goldDark = rgb(0xA97D0C)
    static let mine = rgb(0xD7263D)
    static let drone = rgb(0x3A6EA5)
    static let chaser = rgb(0x7B3FA0)
    static let turret = rgb(0x50555F)
    static let beam = rgb(0xFF3B30)
    static let switchOff = rgb(0x8A8F99)
    static let accent = rgb(0x2FB463)
    static let doorClosed = rgb(0x6B7280)
    static let launchpad = rgb(0xF2994A)
    static let key = rgb(0xE5B80B)
    static let wood = rgb(0x8B5E3C)
    static let button = rgb(0x2B2F38)

    /// Avenir has no CJK glyphs, so Chinese uses PingFang.
    static var titleFont: String { Lang.current == .zh ? "PingFangSC-Semibold" : "AvenirNext-Heavy" }
    static var uiFont: String { Lang.current == .zh ? "PingFangSC-Semibold" : "AvenirNext-DemiBold" }
    static let logoFont = "AvenirNext-Heavy"
    static let monoFont = "Menlo-Bold"
}

enum Progress {
    private static let d = UserDefaults.standard

    /// Number of levels available to play (at least 1).
    static var unlocked: Int {
        max(1, d.integer(forKey: "unlocked"))
    }

    static func best(_ level: Int) -> Double? {
        d.object(forKey: "best_\(level)") as? Double
    }

    static func record(level: Int, timeLeft: Double) {
        if (best(level) ?? -1) < timeLeft { d.set(timeLeft, forKey: "best_\(level)") }
        if unlocked < level + 2 { d.set(min(level + 2, Levels.all.count), forKey: "unlocked") }
    }
}

enum Haptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func heavy() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

/// Rounded button with a label; taps are routed by `BaseScene`.
final class ButtonNode: SKNode {
    let bg: SKShapeNode
    let label = SKLabelNode()
    var action: () -> Void
    var isEnabled = true {
        didSet { alpha = isEnabled ? 1 : 0.45 }
    }
    private let baseColor: UIColor

    init(text: String, size: CGSize, fontSize: CGFloat = 20, color: UIColor = Theme.button,
         textColor: UIColor = Theme.lightText, action: @escaping () -> Void) {
        bg = SKShapeNode(rectOf: size, cornerRadius: min(size.height / 2, 14))
        baseColor = color
        self.action = action
        super.init()
        bg.fillColor = color
        bg.strokeColor = .clear
        addChild(bg)
        label.text = text
        label.fontName = Theme.uiFont
        label.fontSize = fontSize
        label.fontColor = textColor
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        addChild(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setHighlighted(_ on: Bool) {
        bg.fillColor = on ? baseColor.withAlphaComponent(0.7) : baseColor
        bg.setScale(on ? 0.95 : 1)
    }
}

/// Scene base: safe-area-aware layout and button touch routing.
class BaseScene: SKScene {
    var insets: UIEdgeInsets = .zero {
        didSet { if oldValue != insets { layoutScene() } }
    }
    var built = false
    private var buttonTouches: [UITouch: ButtonNode] = [:]

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutScene()
    }

    func layoutScene() {}
    func gameTouchBegan(_ t: UITouch) {}
    func gameTouchMoved(_ t: UITouch) {}
    func gameTouchEnded(_ t: UITouch) {}

    func go(to scene: BaseScene, fade: Bool = true) {
        guard let view else { return }
        scene.scaleMode = .resizeFill
        scene.insets = view.safeAreaInsets
        if fade {
            view.presentScene(scene, transition: .fade(with: Theme.screen, duration: 0.3))
        } else {
            view.presentScene(scene)
        }
    }

    private func isVisible(_ node: SKNode) -> Bool {
        var cur: SKNode? = node
        while let c = cur {
            if c.isHidden || c.alpha < 0.05 { return false }
            cur = c.parent
        }
        return true
    }

    private func button(at p: CGPoint) -> ButtonNode? {
        for n in nodes(at: p) {
            var cur: SKNode? = n
            while let c = cur {
                if let b = c as? ButtonNode, b.isEnabled, isVisible(b) { return b }
                cur = c.parent
            }
        }
        return nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if let b = button(at: t.location(in: self)) {
                buttonTouches[t] = b
                b.setHighlighted(true)
            } else {
                gameTouchBegan(t)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches where buttonTouches[t] == nil { gameTouchMoved(t) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if let b = buttonTouches.removeValue(forKey: t) {
                b.setHighlighted(false)
                // The accumulated frame is in the parent's space, so compare against the touch there.
                if b.calculateAccumulatedFrame().insetBy(dx: -10, dy: -10).contains(t.location(in: b.parent ?? self)) {
                    Sound.shared.play(.tap)
                    b.action()
                }
            } else {
                gameTouchEnded(t)
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if let b = buttonTouches.removeValue(forKey: t) {
                b.setHighlighted(false)
            } else {
                gameTouchEnded(t)
            }
        }
    }
}

func makeLabel(_ text: String, size: CGFloat, font: String = Theme.uiFont, color: UIColor = Theme.text) -> SKLabelNode {
    let l = SKLabelNode(text: text)
    l.fontName = font
    l.fontSize = size
    l.fontColor = color
    l.verticalAlignmentMode = .center
    l.horizontalAlignmentMode = .center
    return l
}
