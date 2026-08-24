import NovaStationCore
import SpriteKit
import UIKit

@MainActor
final class PinballScene: SKScene {
    private enum Layout {
        static let sceneSize = CGSize(width: 1_024, height: 768)
        static let playfieldWidthRatio: CGFloat = 0.70
        static let leftFlipperPivot = TableVisualLayout.leftFlipperPivot.logicalPoint
        static let rightFlipperPivot = TableVisualLayout.rightFlipperPivot.logicalPoint
        static let plungerPosition = NovaStationTable.launchPosition
        static let hudPosition = CGPoint(x: 868, y: 386)
        static let hudSize = CGSize(width: 238, height: 430)
    }

    private weak var model: AppModel?
    private var driver: SimulationDriver
    private var interpreter = TouchInterpreter()
    private var previousUpdateTime: TimeInterval?
    private var lifecycleIsPaused = true
    private var modalOverlayIsPresented = false
    private var didBuildRasterTable = false
    private let leftFlipper = SKSpriteNode(texture: SKTexture(imageNamed: "flipper-left"))
    private let rightFlipper = SKSpriteNode(texture: SKTexture(imageNamed: "flipper-right"))
    private let plungerNode = SKSpriteNode(texture: SKTexture(imageNamed: "plunger"))
    private let hudNode = SKSpriteNode(texture: SKTexture(imageNamed: "hud-overlay"))
    private let menuLayer = SKNode()
    private let launchArtwork = SKSpriteNode(texture: SKTexture(imageNamed: "key-art"))
    private let gameOverArtwork = SKSpriteNode(texture: SKTexture(imageNamed: "store-creative"))
    private var ballNodes: [UInt64: SKSpriteNode] = [:]
    private let hudRenderer = RasterHUDRenderer()
    private var lastHUDContent: RasterHUDRenderer.Content?

    init(model: AppModel) {
        self.model = model
        let initialSession: GameSession
#if DEBUG
        if let scenario = model.mediaScenario,
           let scenarioSession = try? scenario.makeSession() {
            initialSession = scenarioSession
        } else if let freshSession = try? GameSession() {
            initialSession = freshSession
        } else {
            preconditionFailure("The validated Nova Station table could not initialize")
        }
#else
        if let freshSession = try? GameSession() {
            initialSession = freshSession
        } else {
            preconditionFailure("The validated Nova Station table could not initialize")
        }
#endif
        driver = SimulationDriver(session: initialSession)
        driver.setPaused(true)
        super.init(size: Layout.sceneSize)
        scaleMode = .aspectFit
        backgroundColor = .black
        name = "nova-station.scene"
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        guard !didBuildRasterTable else { return }
        didBuildRasterTable = true
        isUserInteractionEnabled = true
        buildRasterTable()
        render(sessionFrame: driver.currentSessionFrame, input: .idle)
    }

    override func update(_ currentTime: TimeInterval) {
        guard !lifecycleIsPaused, let model else { return }
        let elapsed = previousUpdateTime.map { currentTime - $0 } ?? 0
        previousUpdateTime = currentTime
        let input = model.takeSimulationInput()
        let result = driver.advance(elapsed: elapsed, input: input)
        model.receive(sessionFrame: result.sessionFrame, steps: result.stepsExecuted)
        render(sessionFrame: result.sessionFrame, input: driver.isReviewing ? .idle : input.continuous)
    }

    var currentSnapshot: SimulationSnapshot { driver.snapshot }
    var currentRules: GameRulesState { driver.rules }
    var currentPhase: GameSessionPhase { driver.phase }
    var currentReplay: Replay { driver.recording }
    var currentCheckpoint: GameSessionCheckpoint { driver.checkpoint }
    var currentSessionFrame: GameSessionFrame { driver.currentSessionFrame }

    var isAssisted: Bool { driver.isAssisted }
    var isReviewing: Bool { driver.isReviewing }

    func canRewind(to target: RewindTarget) -> Bool {
        driver.canRewind(to: target)
    }

    /// Restores a recorded keyframe and gives the table straight back to the
    /// player at that instant.
    @discardableResult
    func rewind(to target: RewindTarget) throws -> GameSessionFrame {
        let frame = try driver.rewind(to: target)
        previousUpdateTime = nil
        render(sessionFrame: frame, input: .idle)
        return frame
    }

    /// Replays the player's own recorded inputs from a keyframe.
    @discardableResult
    func beginReview(from target: RewindTarget, speed: Double) throws -> GameSessionFrame {
        let frame = try driver.beginReview(from: target, speed: speed)
        previousUpdateTime = nil
        render(sessionFrame: frame, input: .idle)
        return frame
    }

    func endReview() {
        driver.endReview()
        previousUpdateTime = nil
    }

    func markAssisted() {
        driver.markAssisted()
    }

    /// Serves the identical drill session. Every attempt starts here.
    @discardableResult
    func startDrill(_ drill: ShotDrill) throws -> GameSessionFrame {
        driver.replaceSession(try ShotDrillCatalog.makeSession())
        previousUpdateTime = nil
        let frame = driver.currentSessionFrame
        render(sessionFrame: frame, input: .idle)
        return frame
    }

    @discardableResult
    func startNewGame() -> GameSessionFrame {
        do {
            let frame = try driver.startNewGame()
            previousUpdateTime = nil
            render(sessionFrame: frame, input: .idle)
            return frame
        } catch {
            preconditionFailure("The validated Nova Station session could not restart: \(error)")
        }
    }

    func setLifecyclePaused(_ paused: Bool) {
        guard lifecycleIsPaused != paused else { return }
        lifecycleIsPaused = paused
        driver.setPaused(paused)
        previousUpdateTime = nil
    }

    func setModalOverlayPresented(_ presented: Bool) {
        guard modalOverlayIsPresented != presented else { return }
        modalOverlayIsPresented = presented
        updateMenu(for: driver.phase)
    }

    func restore(snapshot: SimulationSnapshot, rules: GameRulesState) throws {
        try driver.restore(snapshot: snapshot, rules: rules)
        previousUpdateTime = nil
        render(sessionFrame: driver.currentSessionFrame, input: .idle)
    }

    func restore(snapshot: SimulationSnapshot, rules: GameRulesState, replay: Replay) throws {
        try driver.restore(snapshot: snapshot, rules: rules, replay: replay)
        previousUpdateTime = nil
        render(sessionFrame: driver.currentSessionFrame, input: .idle)
    }

    func restore(checkpoint: GameSessionCheckpoint) throws {
        try driver.restore(checkpoint: checkpoint)
        previousUpdateTime = nil
        render(sessionFrame: driver.currentSessionFrame, input: .idle)
    }

#if DEBUG
    @discardableResult
    func applyMediaScenario(
        _ scenario: MediaScenario,
        preparedSession: GameSession? = nil
    ) -> GameSessionFrame {
        do {
            let session: GameSession
            if let preparedSession {
                session = preparedSession
            } else {
                session = try scenario.makeSession()
            }
            driver.replaceSession(session)
            previousUpdateTime = nil
            let frame = driver.currentSessionFrame
            render(sessionFrame: frame, input: .idle)
            return frame
        } catch {
            preconditionFailure("Invalid deterministic media scenario \(scenario.rawValue): \(error)")
        }
    }
#endif

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        interpret(touches, phase: .began)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        interpret(touches, phase: .moved)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        interpret(touches, phase: .ended)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        interpret(touches, phase: .cancelled)
    }

    private func interpret(_ touches: Set<UITouch>, phase: TouchSample.Phase) {
        guard let view else { return }
        let samples = touches.map {
            TouchSample(
                id: ObjectIdentifier($0).hashValue,
                phase: phase,
                location: $0.location(in: view),
                timestamp: $0.timestamp
            )
        }
        model?.apply(interpreter.events(for: samples, in: view.bounds))
    }

    private func render(
        sessionFrame: GameSessionFrame,
        input: ContinuousPlayerInput
    ) {
        leftFlipper.zRotation = input.leftFlipperIsPressed ? 0.48 : 0
        rightFlipper.zRotation = input.rightFlipperIsPressed ? -0.48 : 0
        plungerNode.position = Self.scenePoint(for: Layout.plungerPosition)
        plungerNode.position.y -= CGFloat(input.plungerPull) * 42
        syncBallNodes(with: sessionFrame.snapshot.balls)
        updateHUD(for: sessionFrame)
        updateMenu(for: sessionFrame.phase)
    }

    private func syncBallNodes(with balls: [BallState]) {
        let liveIDs = Set(balls.map(\.id))
        for staleID in ballNodes.keys where !liveIDs.contains(staleID) {
            ballNodes.removeValue(forKey: staleID)?.removeFromParent()
        }
        for ball in balls {
            let node: SKSpriteNode
            if let existing = ballNodes[ball.id] {
                node = existing
            } else {
                let texture = SKTexture(imageNamed: "ball")
                texture.filteringMode = .linear
                node = SKSpriteNode(texture: texture, color: .clear, size: CGSize(width: 30, height: 30))
                node.name = "sprite.ball.\(ball.id)"
                node.zPosition = 6
                addChild(node)
                ballNodes[ball.id] = node
            }
            node.position = Self.scenePoint(for: ball.position)
        }
    }

    private func updateHUD(for frame: GameSessionFrame) {
        let content = RasterHUDRenderer.Content(
            score: frame.rules.score,
            ballsRemaining: frame.rules.ballsRemaining,
            ballsInPlay: frame.rules.ballsInPlay,
            mission: frame.rules.missionState,
            clearance: frame.rules.clearance,
            scoreMultiplier: frame.rules.scoreMultiplier,
            bonusMultiplier: frame.rules.bonusMultiplier,
            stationPower: frame.rules.stationPower,
            isTilted: frame.rules.isTilted,
            phase: frame.phase,
            status: model?.statusText ?? ""
        )
        guard content != lastHUDContent else { return }
        lastHUDContent = content
        let texture = SKTexture(image: hudRenderer.image(for: content))
        texture.filteringMode = .linear
        hudNode.texture = texture
    }

    private func updateMenu(for phase: GameSessionPhase) {
        menuLayer.isHidden = modalOverlayIsPresented || phase == .playing
        launchArtwork.isHidden = phase != .launch
        gameOverArtwork.isHidden = phase != .gameOver
    }

    private func buildRasterTable() {
        addRasterNode(
            texture: SKTexture(imageNamed: "table-composition"),
            name: "sprite.table.background",
            position: CGPoint(x: 512, y: 384),
            size: size,
            z: 0
        )
        configureDynamicSprite(
            leftFlipper,
            name: "sprite.flipper.left",
            position: Self.scenePoint(for: Layout.leftFlipperPivot),
            size: CGSize(width: 138, height: 78),
            anchorPoint: CGPoint(x: 0.16, y: 0.50)
        )
        configureDynamicSprite(
            rightFlipper,
            name: "sprite.flipper.right",
            position: Self.scenePoint(for: Layout.rightFlipperPivot),
            size: CGSize(width: 138, height: 78),
            anchorPoint: CGPoint(x: 0.84, y: 0.50)
        )
        configureDynamicSprite(
            plungerNode,
            name: "sprite.plunger",
            position: Self.scenePoint(for: Layout.plungerPosition),
            size: CGSize(width: 116, height: 37),
            anchorPoint: CGPoint(x: 0.88, y: 0.50)
        )
        plungerNode.zRotation = .pi / 2
        configureDynamicSprite(
            hudNode,
            name: "sprite.hud.raster",
            position: Layout.hudPosition,
            size: Layout.hudSize,
            anchorPoint: CGPoint(x: 0.50, y: 0.50)
        )
        hudNode.zPosition = 8
        buildMenuLayer()
    }

    private func buildMenuLayer() {
        menuLayer.name = "sprite.menu.layer"
        menuLayer.zPosition = 30
        launchArtwork.name = "sprite.menu.launch-artwork"
        launchArtwork.position = CGPoint(x: 512, y: 384)
        launchArtwork.size = CGSize(width: 1_152, height: 768)
        launchArtwork.texture?.filteringMode = .linear
        gameOverArtwork.name = "sprite.menu.game-over-artwork"
        gameOverArtwork.position = CGPoint(x: 512, y: 384)
        gameOverArtwork.size = CGSize(width: 1_536, height: 768)
        gameOverArtwork.texture?.filteringMode = .linear
        menuLayer.addChild(launchArtwork)
        menuLayer.addChild(gameOverArtwork)
        addChild(menuLayer)
    }

    private func addRasterNode(
        texture: SKTexture,
        name: String,
        position: CGPoint,
        size: CGSize,
        z: CGFloat
    ) {
        texture.filteringMode = .linear
        let node = SKSpriteNode(texture: texture, color: .clear, size: size)
        node.name = name
        node.position = position
        node.zPosition = z
        addChild(node)
    }

    private func configureDynamicSprite(
        _ node: SKSpriteNode,
        name: String,
        position: CGPoint,
        size: CGSize,
        anchorPoint: CGPoint
    ) {
        node.texture?.filteringMode = .linear
        node.name = name
        node.position = position
        node.size = size
        node.anchorPoint = anchorPoint
        node.zPosition = 5
        addChild(node)
    }

    private static func scenePoint(for vector: Vector2) -> CGPoint {
        CGPoint(
            x: CGFloat(vector.x) * Layout.sceneSize.width * Layout.playfieldWidthRatio,
            y: CGFloat(vector.y / NovaStationTable.definition.playfieldSize.y) * Layout.sceneSize.height
        )
    }
}
