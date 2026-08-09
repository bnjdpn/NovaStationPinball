import AVFAudio
import SpriteKit
import SwiftUI

struct RootView: View {
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { proxy in
                let height = min(proxy.size.height, proxy.size.width * 0.75)
                let width = height * 4.0 / 3.0
                ZStack(alignment: .topLeading) {
                    Color.clear.frame(width: width, height: height)
                    SpriteView(scene: model.scene, options: [.ignoresSiblingOrder])
                        .frame(width: width, height: height)
                        .accessibilityHidden(true)
                }
                .frame(width: width, height: height)
                .overlay {
                    ZStack {
                        Rectangle().fill(.clear)
                            .accessibilityElement(children: .ignore)
                            .accessibilityIdentifier("art.frame.4x3")
                            .accessibilityLabel(Text("accessibility.frame.label"))
                            .accessibilityHint(Text("accessibility.frame.hint"))
                            .accessibilityAction(named: Text(verbatim: model.accessibilityPauseActionTitle)) {
                                model.togglePauseFromAccessibility()
                            }
                        HStack(spacing: 0) {
                            Rectangle().fill(.clear)
                                .frame(width: width * 0.70, height: height)
                                .accessibilityElement(children: .ignore)
                                .accessibilityIdentifier("art.table")
                                .accessibilityLabel(Text("accessibility.table.label"))
                                .accessibilityHint(Text("accessibility.table.hint"))
                                .accessibilityAction(named: Text("accessibility.action.left_flipper")) {
                                    model.toggleFlipperFromAccessibility(.left)
                                }
                                .accessibilityAction(named: Text("accessibility.action.right_flipper")) {
                                    model.toggleFlipperFromAccessibility(.right)
                                }
                                .accessibilityAction(named: Text("accessibility.action.launch_ball")) {
                                    model.launchBallFromAccessibility()
                                }
                                .accessibilityAction(named: Text("accessibility.action.nudge")) {
                                    model.nudgeFromAccessibility()
                                }
                            Rectangle().fill(.clear)
                                .frame(width: width * 0.30, height: height)
                                .accessibilityElement(children: .ignore)
                                .accessibilityIdentifier("art.console")
                                .accessibilityLabel(Text("accessibility.console.label"))
                                .accessibilityValue(model.accessibilityConsoleValue)
                                .accessibilityAddTraits(.updatesFrequently)
                        }
                        if let mediaScenario = model.mediaScenario {
                            Rectangle().fill(.clear)
                                .frame(width: 1, height: 1)
                                .accessibilityElement(children: .ignore)
                                .accessibilityIdentifier("media.scenario.\(mediaScenario.rawValue)")
                                .accessibilityLabel(Text(mediaScenario.rawValue))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .persistentSystemOverlays(.hidden)
        .task {
            model.start()
            await model.runMediaPreviewSequenceIfRequested()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            model.setApplicationActivity(Self.lifecycleActivity(for: phase))
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            handleAudioInterruption(notification)
        }
    }

    private static func lifecycleActivity(for phase: ScenePhase) -> LifecycleApplicationActivity {
        switch phase {
        case .active: .active
        case .inactive: .inactive
        case .background: .background
        @unknown default: .inactive
        }
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return }

        switch type {
        case .began:
            model.audioInterruptionBegan()
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            model.audioInterruptionEnded(shouldResume: options.contains(.shouldResume))
        @unknown default:
            model.audioInterruptionBegan()
        }
    }
}
