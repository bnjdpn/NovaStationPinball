// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NovaStationPinball",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "NovaStationCore", targets: ["NovaStationCore"])
    ],
    targets: [
        .target(name: "NovaStationCore", path: "NovaStationCore/Sources/NovaStationCore"),
        .target(
            name: "NovaStationLifecycle",
            dependencies: ["NovaStationCore"],
            path: "NovaStationPinball",
            exclude: [
                "App/AppModel.swift",
                "App/MediaPreviewHandshake.swift",
                "App/NovaStationPinballApp.swift",
                "App/RootView.swift",
                "Info.plist",
                "NovaStationPinball.entitlements",
                "Resources",
                "StoreKit",
                "Game/PinballScene.swift",
                "Game/RasterHUDRenderer.swift",
                "Game/TouchInterpreter.swift",
                "Services/AudioEngine.swift",
                "Services/GameCenterClient.swift",
                "Services/HapticsService.swift",
                "Services/LocalGameStore.swift",
                "Services/TipJarSupport.swift"
            ],
            sources: [
                "App/GameCompletionGate.swift",
                "App/MediaScenario.swift",
                "Game/SimulationDriver.swift",
                "Services/LifecycleCoordinator.swift"
            ]
        ),
        .testTarget(name: "NovaStationCoreTests", dependencies: ["NovaStationCore"], path: "NovaStationCore/Tests/NovaStationCoreTests"),
        .testTarget(
            name: "NovaStationLifecycleTests",
            dependencies: ["NovaStationLifecycle", "NovaStationCore"],
            path: "NovaStationPinballTests",
            exclude: [
                "AppModelTestSupport.swift",
                "AppModelRuntimeIntegrationTests.swift",
                "AudioEngineTests.swift",
                "BootstrapTests.swift",
                "GameCenterClientTests.swift",
                "HapticsServiceTests.swift",
                "LocalGameStoreTests.swift",
                "OptionalEffectsLifecycleTests.swift",
                "SimulationDriverTests.swift",
                "TipJarSupportTests.swift",
                "TouchInterpreterTests.swift"
            ],
            sources: [
                "LifecycleCoordinatorTests.swift",
                "LocalizationContractTests.swift",
                "MediaScenarioTests.swift",
                "SimulationDriverSessionTests.swift"
            ]
        )
    ]
)
