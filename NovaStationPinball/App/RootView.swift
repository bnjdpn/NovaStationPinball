import AVFAudio
import NovaStationCore
import SpriteKit
import SwiftUI

struct RootView: View {
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var activeOverlay: RootOverlay?
    @State private var tableGuideStep = TableGuideStep.controls
    @State private var tipJarLoadState = TipJarLoadState.idle
    @State private var availableTips: [AvailableTip] = []
    @State private var purchasingTipIdentifier: String?
    @State private var tipPurchaseOutcome: TipPurchaseOutcome?

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
                        if activeOverlay == nil {
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
                .overlay(alignment: .topTrailing) {
                    if activeOverlay == nil {
                        HStack(spacing: 8) {
                            Button {
                                presentTipJar()
                            } label: {
                                Label("tips.open", systemImage: "heart.circle.fill")
                                    .font(.headline)
                            }
                            .foregroundStyle(.mint)
                            .accessibilityIdentifier("tipJarOpen")

                            Button {
                                presentTableGuide()
                            } label: {
                                Label("guide.open", systemImage: "questionmark.circle.fill")
                                    .font(.headline)
                            }
                            .foregroundStyle(.cyan)
                            .accessibilityIdentifier("tableGuideOpen")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.black.opacity(0.84))
                        .padding(max(8, height * 0.02))
                    }
                }
                .overlay {
                    if activeOverlay == .tableGuide {
                        TableGuideOverlay(
                            size: CGSize(width: width, height: height),
                            step: $tableGuideStep,
                            onClose: dismissTableGuide
                        )
                        .transition(.opacity)
                    } else if activeOverlay == .tipJar {
                        TipJarOverlay(
                            size: CGSize(width: width, height: height),
                            loadState: tipJarLoadState,
                            tips: availableTips,
                            purchasingTipIdentifier: purchasingTipIdentifier,
                            purchaseOutcome: tipPurchaseOutcome,
                            onPurchase: { tip in
                                Task { await purchaseTip(tip) }
                            },
                            onClose: dismissTipJar
                        )
                        .task {
                            await loadTipsIfNeeded()
                        }
                        .transition(.opacity)
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
        .onChange(of: model.mediaScenario) { _, scenario in
            synchronizePreviewTableGuide(for: scenario)
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            handleAudioInterruption(notification)
        }
    }

    private func presentTableGuide(step: TableGuideStep = .controls) {
        guard activeOverlay == nil else { return }
        model.beginModalOverlay()
        tableGuideStep = step
        withAnimation(.easeOut(duration: 0.18)) {
            activeOverlay = .tableGuide
        }
    }

    private func dismissTableGuide() {
        guard activeOverlay == .tableGuide else { return }
        withAnimation(.easeIn(duration: 0.16)) {
            activeOverlay = nil
        }
        model.endModalOverlay()
    }

    private func presentTipJar() {
        guard activeOverlay == nil else { return }
        availableTips = []
        tipJarLoadState = .idle
        tipPurchaseOutcome = nil
        purchasingTipIdentifier = nil
        model.beginModalOverlay()
        withAnimation(.easeOut(duration: 0.18)) {
            activeOverlay = .tipJar
        }
    }

    private func dismissTipJar() {
        guard activeOverlay == .tipJar else { return }
        withAnimation(.easeIn(duration: 0.16)) {
            activeOverlay = nil
        }
        model.endModalOverlay()
    }

    private func loadTipsIfNeeded() async {
        guard tipJarLoadState == .idle else { return }
        tipJarLoadState = .loading
        let tips = await model.availableTips()
        guard !Task.isCancelled else { return }
        availableTips = tips
        tipJarLoadState = tips.isEmpty ? .unavailable : .available
    }

    private func purchaseTip(_ tip: AvailableTip) async {
        guard purchasingTipIdentifier == nil else { return }
        purchasingTipIdentifier = tip.definition.productIdentifier
        tipPurchaseOutcome = nil
        let outcome = await model.purchaseTip(
            productIdentifier: tip.definition.productIdentifier
        )
        guard !Task.isCancelled else { return }
        tipPurchaseOutcome = outcome
        purchasingTipIdentifier = nil
    }

    private func synchronizePreviewTableGuide(for scenario: MediaScenario?) {
        guard model.runsMediaPreviewSequence else { return }
        if scenario == .mission {
            presentTableGuide(step: .missions)
        } else if activeOverlay == .tableGuide {
            dismissTableGuide()
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

private enum RootOverlay: Equatable {
    case tableGuide
    case tipJar
}

private enum TipJarLoadState: Equatable {
    case idle
    case loading
    case available
    case unavailable
}

private struct TipJarOverlay: View {
    let size: CGSize
    let loadState: TipJarLoadState
    let tips: [AvailableTip]
    let purchasingTipIdentifier: String?
    let purchaseOutcome: TipPurchaseOutcome?
    let onPurchase: (AvailableTip) -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            // Keep the game completely out of the visual and accessibility
            // surface while this modal is open. A translucent scrim leaves
            // inaccessible playfield copy visible to system audits.
            Color.black
                .contentShape(Rectangle())

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .accessibilityHidden(true)
                        Text("tips.title")
                            .accessibilityIdentifier("tipJarTitle")
                    }
                    .font(.headline)
                    Spacer(minLength: 8)
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .accessibilityHidden(true)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.mint)
                    .accessibilityLabel(Text("tips.close"))
                    .accessibilityIdentifier("tipJarClose")
                }

                Text("tips.body")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("tipJarBody")

                Divider()
                    .overlay(.white.opacity(0.72))

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        switch loadState {
                        case .idle, .loading:
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("tips.loading")
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("tipJarStatus")
                        case .unavailable:
                            Text("tips.unavailable")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("tipJarStatus")
                        case .available:
                            ForEach(tips, id: \.definition.id) { tip in
                                Button {
                                    onPurchase(tip)
                                } label: {
                                    HStack(spacing: 12) {
                                        Text(verbatim: tip.displayName)
                                            .multilineTextAlignment(.leading)
                                        Spacer(minLength: 8)
                                        Text(verbatim: tip.displayPrice)
                                            .fontWeight(.semibold)
                                            .monospacedDigit()
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Color(red: 0.42, green: 1.0, blue: 0.78))
                                .foregroundStyle(.black)
                                .disabled(purchasingTipIdentifier != nil)
                                .accessibilityLabel(
                                    Text(verbatim: "\(tip.displayName), \(tip.displayPrice)")
                                )
                                .accessibilityHint(Text("tips.purchase.hint"))
                                .accessibilityIdentifier("tipJarPurchase.\(tip.definition.id)")
                            }
                        }

                        if let purchaseOutcome {
                            Text(purchaseOutcome.localizedStatusKey)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("tipJarStatus")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .foregroundStyle(.white)
            .padding(14)
            .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
            .background(
                Color(red: 0.055, green: 0.065, blue: 0.085),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("tipJar")
            .accessibilityLabel(Text("tips.title"))
            .accessibilityAddTraits(.isModal)
        }
        .frame(width: size.width, height: size.height)
    }

    private var cardWidth: CGFloat {
        min(size.width - 24, max(280, size.width * 0.56))
    }

    private var cardHeight: CGFloat {
        min(size.height - 24, max(250, size.height * 0.88))
    }
}

private extension TipPurchaseOutcome {
    var localizedStatusKey: LocalizedStringKey {
        switch self {
        case .purchased: "tips.outcome.purchased"
        case .pending: "tips.outcome.pending"
        case .cancelled: "tips.outcome.cancelled"
        case .unavailable: "tips.outcome.unavailable"
        case .unverified: "tips.outcome.unverified"
        }
    }
}

private enum TableGuideStep: Int, CaseIterable {
    case controls
    case missions
    case progress

    var identifier: String {
        switch self {
        case .controls: "controls"
        case .missions: "missions"
        case .progress: "progress"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .controls: "guide.controls.title"
        case .missions: "guide.missions.title"
        case .progress: "guide.progress.title"
        }
    }

    var body: LocalizedStringKey {
        switch self {
        case .controls: "guide.controls.body"
        case .missions: "guide.missions.body"
        case .progress: "guide.progress.body"
        }
    }

    var anchors: [TableVisualAnchor] {
        switch self {
        case .controls:
            [
                TableVisualLayout.leftFlipperPivot,
                TableVisualLayout.rightFlipperPivot,
                TableVisualLayout.plunger,
            ]
        case .missions:
            [
                TableVisualLayout.missionSelectLane,
                TableVisualLayout.missionStartLane,
                TableVisualLayout.missionAcknowledgeLane,
            ]
        case .progress:
            [
                TableVisualLayout.stationPower,
                TableVisualLayout.multiball,
                TableVisualLayout.portal,
            ]
        }
    }

    var previous: TableGuideStep? {
        TableGuideStep(rawValue: rawValue - 1)
    }

    var next: TableGuideStep? {
        TableGuideStep(rawValue: rawValue + 1)
    }
}

private enum TableGuideLayoutContract {
    static let edgeInset: CGFloat = 12
    static let markerClearance: CGFloat = 8
    static let controlsWidthFraction: CGFloat = 0.58
    static let controlsHeightFraction: CGFloat = 0.60
    static let controlsMinimumWidth: CGFloat = 240
    static let controlsMinimumHeight: CGFloat = 180
}

private struct TableGuideOverlay: View {
    let size: CGSize
    @Binding var step: TableGuideStep
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.72)
                .contentShape(Rectangle())

            Rectangle().fill(.clear)
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("tableGuide")
                .accessibilityLabel(Text("guide.title"))
                .accessibilityAddTraits(.isModal)
                .allowsHitTesting(false)

            ForEach(Array(step.anchors.enumerated()), id: \.offset) { index, anchor in
                ZStack {
                    Circle()
                        .fill(.black.opacity(0.78))
                    Circle()
                        .stroke(.cyan, lineWidth: 3)
                    Text("\(index + 1)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                }
                .frame(width: markerDiameter, height: markerDiameter)
                .position(position(for: anchor))
                .accessibilityHidden(true)
            }

            guideCard

            Rectangle().fill(.clear)
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("tableGuideStep.\(step.identifier)")
                .accessibilityLabel(Text(step.title))
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
    }

    private var guideCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("guide.title", systemImage: "map.fill")
                    .font(.headline)
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.cyan)
                .accessibilityLabel(Text("guide.close"))
                .accessibilityIdentifier("tableGuideClose")
            }

            Text("\(step.rawValue + 1) / \(TableGuideStep.allCases.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(step.title)
                        .font(.title3.bold())
                    Text(step.body)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                Button {
                    guard let previous = step.previous else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        step = previous
                    }
                } label: {
                    Label("guide.previous", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .disabled(step.previous == nil)
                .accessibilityIdentifier("tableGuidePrevious")

                Spacer(minLength: 4)

                if let next = step.next {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            step = next
                        }
                    } label: {
                        Label("guide.next", systemImage: "chevron.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .accessibilityIdentifier("tableGuideNext")
                } else {
                    Button("guide.close", action: onClose)
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                        .accessibilityIdentifier("tableGuideDone")
                }
            }
        }
        .padding(14)
        .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.cyan.opacity(0.48), lineWidth: 1)
        }
        .position(cardPosition)
    }

    private var cardWidth: CGFloat {
        switch step {
        case .controls:
            min(
                size.width - 2 * TableGuideLayoutContract.edgeInset,
                max(
                    TableGuideLayoutContract.controlsMinimumWidth,
                    size.width * TableGuideLayoutContract.controlsWidthFraction
                )
            )
        case .missions, .progress:
            min(size.width * 0.38, max(210, size.width * 0.29))
        }
    }

    private var cardHeight: CGFloat {
        switch step {
        case .controls:
            min(controlsPreferredHeight, controlsCollisionSafeHeight)
        case .missions, .progress:
            max(220, size.height - 24)
        }
    }

    private var cardPosition: CGPoint {
        switch step {
        case .controls:
            CGPoint(
                x: size.width - cardWidth / 2 - TableGuideLayoutContract.edgeInset,
                y: cardHeight / 2 + TableGuideLayoutContract.edgeInset
            )
        case .missions:
            CGPoint(x: cardWidth / 2 + 12, y: size.height / 2)
        case .progress:
            CGPoint(x: size.width - cardWidth / 2 - 12, y: size.height / 2)
        }
    }

    private var markerDiameter: CGFloat {
        min(54, max(34, size.height * 0.085))
    }

    private var controlsPreferredHeight: CGFloat {
        min(
            size.height - 2 * TableGuideLayoutContract.edgeInset,
            max(
                TableGuideLayoutContract.controlsMinimumHeight,
                size.height * TableGuideLayoutContract.controlsHeightFraction
            )
        )
    }

    private var controlsCollisionSafeHeight: CGFloat {
        let nearestMarkerTop = TableGuideStep.controls.anchors.map { anchor in
            position(for: anchor).y - markerDiameter / 2
        }.min() ?? size.height
        return max(
            1,
            nearestMarkerTop - TableGuideLayoutContract.edgeInset -
                TableGuideLayoutContract.markerClearance
        )
    }

    private func position(for anchor: TableVisualAnchor) -> CGPoint {
        CGPoint(
            x: size.width * CGFloat(anchor.pixelX / Double(TableVisualLayout.canvasWidth)),
            y: size.height * CGFloat(1 - anchor.pixelY / Double(TableVisualLayout.canvasHeight))
        )
    }
}
