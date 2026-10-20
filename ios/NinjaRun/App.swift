import UIKit
import SpriteKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = GameViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
}

final class GameViewController: UIViewController {
    private var skView: SKView { view as! SKView }

    override func loadView() {
        view = SKView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        skView.ignoresSiblingOrder = false
        skView.isMultipleTouchEnabled = true
        skView.preferredFramesPerSecond = 60
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if skView.scene == nil, view.bounds.width > 0 {
            var first: BaseScene = MenuScene(size: view.bounds.size)
            #if DEBUG
            // Screenshot helper: launch with `-screen levels` or `-screen level3`.
            if let screen = UserDefaults.standard.string(forKey: "screen") {
                if screen == "levels" {
                    first = LevelSelectScene(size: view.bounds.size)
                } else if let n = Int(screen.dropFirst(5)), (1...Levels.all.count).contains(n) {
                    first = GameScene(size: view.bounds.size, level: n - 1)
                }
            }
            #endif
            first.scaleMode = .resizeFill
            first.insets = view.safeAreaInsets
            skView.presentScene(first)
        }
        (skView.scene as? BaseScene)?.insets = view.safeAreaInsets
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
}
