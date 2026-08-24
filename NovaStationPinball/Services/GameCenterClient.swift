import GameKit
import UIKit

@MainActor
protocol GameCenterClient: AnyObject {
    var isAvailable: Bool { get }
    var isAuthenticated: Bool { get }
    func authenticate()
    func submit(score: Int)
}

@MainActor
final class NullGameCenterClient: GameCenterClient {
    let isAvailable = false
    let isAuthenticated = false

    func authenticate() {}
    func submit(score: Int) {}
}

@MainActor
final class GameKitGameCenterClient: GameCenterClient {
    typealias AuthenticationPresenter = @MainActor (UIViewController) -> Void

    private let leaderboardIDs: [String]
    private let presenter: AuthenticationPresenter
    private var hasRequestedAuthentication = false
    var isAvailable: Bool { true }
    var isAuthenticated: Bool { GKLocalPlayer.local.isAuthenticated }
    var canPresentAuthentication: Bool { true }

    init(
        leaderboardIDs: [String] = ["com.bnjdpn.NovaStationPinball.score.high"],
        presenter: @escaping AuthenticationPresenter = GameKitGameCenterClient.presentAuthenticationController
    ) {
        self.leaderboardIDs = leaderboardIDs
        self.presenter = presenter
    }

    func authenticate() {
        guard !hasRequestedAuthentication else { return }
        hasRequestedAuthentication = true
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, _ in
            guard let self, let viewController else { return }
            self.presenter(viewController)
        }
    }

    func submit(score: Int) {
        guard isAuthenticated, score >= 0, !leaderboardIDs.isEmpty else { return }
        GKLeaderboard.submitScore(
            score,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: leaderboardIDs
        ) { _ in
            // Remote reporting is best-effort; the local score is authoritative.
        }
    }

    private static func presentAuthenticationController(_ controller: UIViewController) {
        guard controller.presentingViewController == nil,
              let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let window = windowScene.windows.first(where: \.isKeyWindow)
                ?? windowScene.windows.first(where: { !$0.isHidden }),
              let rootViewController = window.rootViewController
        else { return }

        let presenter = topViewController(from: rootViewController)
        guard presenter.presentedViewController == nil else { return }
        presenter.present(controller, animated: true)
    }

    private static func topViewController(from controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController {
            return topViewController(from: presented)
        }
        if let navigationController = controller as? UINavigationController,
           let visible = navigationController.visibleViewController {
            return topViewController(from: visible)
        }
        if let tabController = controller as? UITabBarController,
           let selected = tabController.selectedViewController {
            return topViewController(from: selected)
        }
        return controller
    }
}
