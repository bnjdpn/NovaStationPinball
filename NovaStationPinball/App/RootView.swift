import AVFAudio
import NovaStationCore
import SpriteKit
import SwiftUI

/// Workshop and paywall palette. Deep console blacks with a single cyan
/// instrument accent, plus one warm amber reserved for the purchase action so
/// it never competes with a gameplay control.
enum WorkshopPalette {
    static let surface = Color(red: 0.055, green: 0.065, blue: 0.085)
    static let raisedSurface = Color(red: 0.094, green: 0.110, blue: 0.140)
    static let instrument = Color(red: 0.35, green: 0.86, blue: 0.98)
    static let purchase = Color(red: 1.0, green: 0.76, blue: 0.32)
    static let hairline = Color(red: 0.35, green: 0.86, blue: 0.98).opacity(0.42)
    /// A control that has nothing to offer yet keeps a solid, readable fill
    /// instead of the system's dimmed disabled treatment, which drops below
    /// the AA contrast floor on this palette.
    static let unavailable = Color(red: 0.20, green: 0.24, blue: 0.30)
}

struct RootView: View {
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var activeOverlay: RootOverlay?
    @State private var tableGuideStep = TableGuideStep.controls
    @State private var workshopMessage: WorkshopMessage?
    @State private var reviewSpeed = ReviewSpeed.full
#if DEBUG
    @State private var didOpenLaunchPaywall = false
#endif

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
#if DEBUG
                        if let mediaScenario = model.mediaScenario {
                            Rectangle().fill(.clear)
                                .frame(width: 1, height: 1)
                                .accessibilityElement(children: .ignore)
                                .accessibilityIdentifier("media.scenario.\(mediaScenario.rawValue)")
                                .accessibilityLabel(Text(mediaScenario.rawValue))
                        }
                        if model.mediaPreviewTimelineStarted {
                            Rectangle().fill(.clear)
                                .frame(width: 1, height: 1)
                                .accessibilityElement(children: .ignore)
                                .accessibilityIdentifier("media.timeline.started")
                                .accessibilityLabel(Text(verbatim: "Media timeline started"))
                        }
#endif
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if activeOverlay == nil {
                        VStack(alignment: .trailing, spacing: 8) {
                            HStack(spacing: 8) {
                                if model.isReviewingBall {
                                    Button {
                                        model.resumeFromReview()
                                    } label: {
                                        Label("workshop.resume", systemImage: "play.circle.fill")
                                            .font(.headline)
                                    }
                                    .foregroundStyle(WorkshopPalette.purchase)
                                    .accessibilityIdentifier("workshopResume")
                                }

                                Button {
                                    presentWorkshop()
                                } label: {
                                    Label("workshop.open", systemImage: "gobackward")
                                        .font(.headline)
                                }
                                .foregroundStyle(WorkshopPalette.instrument)
                                .accessibilityIdentifier("workshopOpen")

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

                            if let drill = model.activeDrill {
                                DrillAttemptPanel(
                                    drill: drill,
                                    outcome: model.activeDrillOutcome,
                                    remainingSeconds: model.activeDrillRemainingSeconds,
                                    record: model.drillEntry(for: drill),
                                    onRetry: { _ = model.restartActiveDrill() },
                                    onExit: { model.endDrill() }
                                )
                                .frame(
                                    maxWidth: max(220, width * 0.36),
                                    maxHeight: max(140, height * 0.62)
                                )
                            }
                        }
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
                    } else if activeOverlay == .workshop {
                        WorkshopOverlay(
                            size: CGSize(width: width, height: height),
                            model: model,
                            reviewSpeed: $reviewSpeed,
                            message: workshopMessage,
                            onRewind: { target in perform(model.rewind(to: target)) },
                            onReview: { target in
                                perform(model.reviewBall(from: target, speed: reviewSpeed.rate))
                            },
                            onDrill: { drill in perform(model.startDrill(drill)) },
                            onUnlock: presentPaywall,
                            onClose: dismissWorkshop
                        )
                        .transition(.opacity)
                    } else if activeOverlay == .paywall {
                        PaywallOverlay(
                            size: CGSize(width: width, height: height),
                            store: model.store,
                            onPurchase: { Task { await model.store.purchase() } },
                            onRestore: { Task { await model.store.restorePurchases() } },
                            onClose: dismissPaywall
                        )
                        .task { await model.store.loadOfferIfNeeded() }
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .persistentSystemOverlays(.hidden)
        .task {
            model.start()
#if DEBUG
            openLaunchPaywallIfRequested()
            await model.runMediaPreviewSequenceIfRequested()
#endif
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            model.setApplicationActivity(Self.lifecycleActivity(for: phase))
        }
#if DEBUG
        .onChange(of: model.mediaScenario) { _, scenario in
            synchronizePreviewTableGuide(for: scenario)
        }
#endif
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

    private func presentWorkshop() {
        guard activeOverlay == nil else { return }
        workshopMessage = nil
        model.beginModalOverlay()
        withAnimation(.easeOut(duration: 0.18)) {
            activeOverlay = .workshop
        }
    }

    private func dismissWorkshop() {
        guard activeOverlay == .workshop else { return }
        workshopMessage = nil
        withAnimation(.easeIn(duration: 0.16)) {
            activeOverlay = nil
        }
        model.endModalOverlay()
    }

    /// The paywall replaces the Workshop sheet instead of stacking on it, so
    /// the game underneath stays paused exactly once.
    private func presentPaywall() {
        workshopMessage = nil
        if activeOverlay == nil { model.beginModalOverlay() }
        withAnimation(.easeOut(duration: 0.18)) {
            activeOverlay = .paywall
        }
    }

    private func dismissPaywall() {
        guard activeOverlay == .paywall else { return }
        withAnimation(.easeIn(duration: 0.16)) {
            activeOverlay = nil
        }
        model.endModalOverlay()
    }

#if DEBUG
    private func openLaunchPaywallIfRequested() {
        guard model.opensPaywallOnLaunch, !didOpenLaunchPaywall else { return }
        didOpenLaunchPaywall = true
        presentPaywall()
    }
#endif

    /// Every Workshop action funnels its refusal into the same two places:
    /// the paywall, or an explicit in-sheet explanation.
    private func perform(_ outcome: AppModel.WorkshopRequestOutcome) {
        switch outcome {
        case .done:
            workshopMessage = nil
            dismissWorkshop()
        case .needsWorkshop:
            presentPaywall()
        case .noKeyframe:
            workshopMessage = .noKeyframe
        }
    }

#if DEBUG
    private func synchronizePreviewTableGuide(for scenario: MediaScenario?) {
        guard model.runsMediaPreviewSequence else { return }
        if scenario == .mission {
            presentTableGuide(step: .missions)
        } else if activeOverlay == .tableGuide {
            dismissTableGuide()
        }
    }
#endif

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
    case workshop
    case paywall
}

enum WorkshopMessage: Equatable {
    case noKeyframe

    var localizedKey: LocalizedStringKey {
        switch self {
        case .noKeyframe: "workshop.message.no_keyframe"
        }
    }
}

enum ReviewSpeed: Equatable, CaseIterable {
    case full
    case half

    var rate: Double {
        switch self {
        case .full: 1
        case .half: 0.5
        }
    }

    var identifier: String {
        switch self {
        case .full: "1x"
        case .half: "0.5x"
        }
    }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .full: "workshop.review.speed.full"
        case .half: "workshop.review.speed.half"
        }
    }
}

/// Drill names live in the catalog under a key built at runtime. Interpolating
/// that key into a `LocalizedStringKey` would make SwiftUI look up the literal
/// "drill.%@" and print the raw key on screen, so the lookup is explicit.
private func drillName(_ drill: ShotDrill) -> String {
    String(localized: String.LocalizationValue(stringLiteral: "drill.\(drill.id)"))
}

/// Success rate, attempt count and best streak for one drill, or the designed
/// empty state shown before the very first attempt.
private func drillRecordText(_ entry: DrillProgressEntry) -> String {
    guard entry.attempts > 0 else {
        return String(localized: "workshop.drills.untried")
    }
    return String.localizedStringWithFormat(
        String(localized: "workshop.drills.record"),
        Int(entry.successRate * 100),
        entry.attempts,
        entry.bestStreak
    )
}

/// The attempt currently on the table: how much of the budget is left, how the
/// attempt ended, and the two controls that close the loop — serve the same
/// shot again, or leave the drill and get an ordinary game back.
private struct DrillAttemptPanel: View {
    let drill: ShotDrill
    let outcome: ShotDrillEvaluator.Outcome
    let remainingSeconds: Int
    let record: DrillProgressEntry
    let onRetry: () -> Void
    let onExit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The read-out scrolls inside the panel and the two controls stay
            // pinned below it, so an attempt can always be served again or
            // left, whatever the text size does to the copy above.
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text(verbatim: drillName(drill))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("workshopDrillName")
                    } icon: {
                        Image(systemName: "target")
                            .accessibilityHidden(true)
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(WorkshopPalette.instrument)

                    Text(verbatim: statusText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(outcome == .running ? Color.white : WorkshopPalette.purchase)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("workshopDrillStatus")

                    Text(verbatim: drillRecordText(record))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("workshopDrillRecord")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            HStack(spacing: 8) {
                Button(action: onRetry) {
                    Text("drill.hud.retry")
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(WorkshopPalette.instrument)
                .foregroundStyle(Color.black)
                .accessibilityIdentifier("workshopDrillRetry")

                Button(action: onExit) {
                    Text("drill.hud.exit")
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(WorkshopPalette.instrument)
                .accessibilityIdentifier("workshopDrillExit")
            }
        }
        .font(.caption)
        .foregroundStyle(.white)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            WorkshopPalette.surface,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        // The panel is a corner read-out over a landscape playfield: past this
        // size it would cover the table it comments on. The same numbers are
        // available at every text size in the Workshop sheet, which scrolls.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workshopDrillHUD")
        .accessibilityLabel(Text("drill.hud.title"))
    }

    /// The attempt speaks for itself on screen: a countdown while it runs, an
    /// explicit verdict the moment it is decided.
    private var statusText: String {
        switch outcome {
        case .running:
            String.localizedStringWithFormat(
                String(localized: "drill.hud.remaining"),
                remainingSeconds
            )
        case .succeeded:
            String(localized: "drill.hud.succeeded")
        case .failed:
            String(localized: "drill.hud.failed")
        }
    }
}

private struct WorkshopOverlay: View {
    let size: CGSize
    let model: AppModel
    @Binding var reviewSpeed: ReviewSpeed
    let message: WorkshopMessage?
    let onRewind: (RewindTarget) -> Void
    let onReview: (RewindTarget) -> Void
    let onDrill: (ShotDrill) -> Void
    let onUnlock: () -> Void
    let onClose: () -> Void

    private let rewindTargets: [(RewindTarget, LocalizedStringKey)] = [
        (.threeSeconds, "workshop.rewind.three"),
        (.fiveSeconds, "workshop.rewind.five"),
        (.ballStart, "workshop.rewind.ball_start")
    ]

    var body: some View {
        ZStack {
            // The playfield leaves the visual and accessibility surface while
            // this modal is open: a translucent scrim would leave unreachable
            // gameplay copy exposed to system audits.
            Color.black
                .contentShape(Rectangle())

            VStack(alignment: .leading, spacing: 10) {
                header

                // Everything below the header scrolls, intro copy included: at
                // the largest accessibility text sizes a fixed intro ate the
                // whole card and collapsed this scroll area to nothing, which
                // put every Workshop control — the unlock button among them —
                // out of reach.
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(model.hasWorkshop ? "workshop.body.owned" : "workshop.body.free")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("workshopBody")

                        supportLinks

                        Divider().overlay(WorkshopPalette.hairline)

                        rewindSection
                        reviewSection
                        drillSection
                        if let message {
                            Text(message.localizedKey)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("workshopStatus")
                        }

                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
                .accessibilityIdentifier("workshopScroll")
            }
            .foregroundStyle(.white)
            .padding(14)
            .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
            .background(
                WorkshopPalette.surface,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("workshop")
            .accessibilityLabel(Text("workshop.title"))
            .accessibilityAddTraits(.isModal)
        }
        .frame(width: size.width, height: size.height)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 6) {
                Image(systemName: "gobackward")
                    .accessibilityHidden(true)
                Text("workshop.title")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("workshopTitle")
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
            .foregroundStyle(WorkshopPalette.instrument)
            .accessibilityLabel(Text("workshop.close"))
            .accessibilityIdentifier("workshopClose")
        }
    }

    /// Support remains available after purchase, inside the Workshop's own
    /// scrolling content. Keeping these links out of the fixed header leaves
    /// the title and close control enough room at accessibility text sizes.
    /// The framed labels, rather than the shorthand `Link` initializer, make
    /// the complete 44-point targets visible to the accessibility system.
    private var supportLinks: some View {
        HStack(spacing: 8) {
            Link(destination: supportURL) {
                Text("paywall.link.support")
                    .underline()
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("workshopSupportLink")
            Link(destination: privacyURL) {
                Text("paywall.link.privacy")
                    .underline()
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("workshopPrivacyLink")
        }
        .font(.footnote)
        .foregroundStyle(WorkshopPalette.instrument)
        .tint(WorkshopPalette.instrument)
    }

    private var rewindSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("workshop.rewind.title")
            HStack(spacing: 8) {
                ForEach(rewindTargets, id: \.0.identifier) { target, title in
                    let isReady = model.canRewind(to: target)
                    Button {
                        onRewind(target)
                    } label: {
                        Text(title)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isReady ? WorkshopPalette.instrument : WorkshopPalette.unavailable)
                    .foregroundStyle(isReady ? Color.black : Color.white)
                    .accessibilityHint(Text(isReady ? "workshop.rewind.hint" : "workshop.message.no_keyframe"))
                    .accessibilityIdentifier("workshopRewind.\(target.identifier)")
                }
            }
            Text(verbatim: rewindAllowanceText)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("workshopRewindAllowance")
            if model.isFounder, !model.hasWorkshop {
                Label {
                    Text("workshop.founder")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(WorkshopPalette.purchase)
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))
                .accessibilityIdentifier("workshopFounder")
            }
            if !model.hasWorkshop {
                unlockButton
            }
        }
    }

    private var rewindAllowanceText: String {
        if model.hasWorkshop { return String(localized: "workshop.rewind.unlimited") }
        return String.localizedStringWithFormat(
            String(localized: "workshop.rewind.remaining"),
            model.remainingFreeRewinds,
            model.freeRewindsPerGame
        )
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("workshop.review.title")
            Picker("workshop.review.speed", selection: $reviewSpeed) {
                ForEach(ReviewSpeed.allCases, id: \.identifier) { speed in
                    Text(speed.localizedKey).tag(speed)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("workshopReviewSpeed")

            reviewButton(
                target: .ballStart,
                title: "workshop.review.ball",
                identifier: "workshopReview.ball-start"
            )
            reviewButton(
                target: .fiveSeconds,
                title: "workshop.review.five",
                identifier: "workshopReview.back-5"
            )
        }
    }

    /// Review controls keep a solid readable fill in both states: the system
    /// disabled treatment on this palette falls under the AA contrast floor,
    /// and a tap on an empty timeline explains itself instead of doing nothing
    /// silently.
    private func reviewButton(
        target: RewindTarget,
        title: LocalizedStringKey,
        identifier: String
    ) -> some View {
        let isReady = model.canRewind(to: target)
        return Button {
            onReview(target)
        } label: {
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(isReady ? WorkshopPalette.instrument : WorkshopPalette.unavailable)
        .foregroundStyle(isReady ? Color.black : Color.white)
        .accessibilityHint(Text(isReady ? "workshop.review.hint" : "workshop.message.no_keyframe"))
        .accessibilityIdentifier(identifier)
    }

    private var drillSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("workshop.drills.title")
            Text("workshop.drills.body")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(ShotDrillCatalog.drills) { drill in
                Button {
                    onDrill(drill)
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: drillName(drill))
                                .multilineTextAlignment(.leading)
                            Text(drillDetail(for: drill))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.74))
                        }
                        Spacer(minLength: 8)
                        if !model.hasWorkshop {
                            Image(systemName: "lock.fill")
                                .accessibilityHidden(true)
                                .foregroundStyle(WorkshopPalette.purchase)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .tint(WorkshopPalette.instrument)
                .accessibilityIdentifier("workshopDrill.\(drill.id)")
            }
        }
    }

    private func drillDetail(for drill: ShotDrill) -> String {
        drillRecordText(model.drillEntry(for: drill))
    }

    private var unlockButton: some View {
        Button(action: onUnlock) {
            Text("workshop.unlock")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(WorkshopPalette.purchase)
        .foregroundStyle(.black)
        .accessibilityIdentifier("workshopUnlock")
    }

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.subheadline.bold())
            .foregroundStyle(WorkshopPalette.instrument)
    }

    private var privacyURL: URL {
        URL(string: WorkshopCatalog.privacyURL) ?? URL(fileURLWithPath: "/")
    }

    private var supportURL: URL {
        URL(string: WorkshopCatalog.supportURL) ?? URL(fileURLWithPath: "/")
    }

    /// The sheet is a full modal over a black scrim, so it takes the room it
    /// needs: a narrow card forced French copy to wrap until rows were cut in
    /// half by the scroll edge.
    private var cardWidth: CGFloat {
        min(size.width - 24, max(320, size.width * 0.86))
    }

    /// The modal uses the whole frame it is given: any content row clipped in
    /// half by the scroll edge is reported by the system accessibility audit.
    private var cardHeight: CGFloat {
        max(250, size.height - 24)
    }
}

private struct PaywallOverlay: View {
    let size: CGSize
    let store: StoreService
    let onPurchase: () -> Void
    let onRestore: () -> Void
    let onClose: () -> Void

    private struct UnlockedFeature: Identifiable {
        let id: String
        let symbol: String
        var key: LocalizedStringKey { LocalizedStringKey(id) }
    }

    private let unlockedFeatures: [UnlockedFeature] = [
        UnlockedFeature(id: "paywall.feature.rewind", symbol: "gobackward"),
        UnlockedFeature(id: "paywall.feature.review", symbol: "play.rectangle"),
        UnlockedFeature(id: "paywall.feature.drills", symbol: "target"),
        UnlockedFeature(id: "paywall.feature.stats", symbol: "chart.bar")
    ]

    var body: some View {
        ZStack {
            Color.black
                .contentShape(Rectangle())

            VStack(alignment: .leading, spacing: 10) {
                header

                Divider().overlay(WorkshopPalette.hairline)

                // Landscape modal, two columns: what the purchase unlocks on
                // the left, the decision itself on the right. The offer, its
                // price, Restore and the legal block therefore never fall
                // below a fold, in any language.
                HStack(alignment: .top, spacing: 16) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("paywall.body")
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("paywallBody")

                            // Explicit row rather than `Label`: the system audit
                            // reports a Label's text as clippable at larger
                            // Dynamic Type sizes even inside a scroll view.
                            ForEach(unlockedFeatures) { feature in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Image(systemName: feature.symbol)
                                        .foregroundStyle(WorkshopPalette.instrument)
                                        .accessibilityHidden(true)
                                    Text(feature.key)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .font(.callout)
                            }

                            Text("paywall.free_forever")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.82))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityIdentifier("paywallScroll")

                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            offerSection

                            Text("paywall.one_time")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.82))
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("paywallTerms")

                            VStack(alignment: .leading, spacing: 0) {
                                Link(destination: termsURL) {
                                    Text("paywall.link.terms")
                                        .underline()
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityIdentifier("paywallTermsLink")
                                Link(destination: privacyURL) {
                                    Text("paywall.link.privacy")
                                        .underline()
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityIdentifier("paywallPrivacyLink")
                            }
                            .font(.footnote)
                            .foregroundStyle(WorkshopPalette.instrument)
                            .tint(WorkshopPalette.instrument)

                            if let statusKey {
                                Text(statusKey)
                                    .font(.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("paywallStatus")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityIdentifier("paywallDecisionScroll")
                    .frame(width: decisionColumnWidth)
                }
            }
            .foregroundStyle(.white)
            .padding(14)
            .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
            .background(
                WorkshopPalette.surface,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("paywall")
            .accessibilityLabel(Text("paywall.title"))
            .accessibilityAddTraits(.isModal)
        }
        .frame(width: size.width, height: size.height)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .accessibilityHidden(true)
                Text("paywall.title")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("paywallTitle")
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
            .foregroundStyle(WorkshopPalette.instrument)
            .accessibilityLabel(Text("paywall.close"))
            .accessibilityIdentifier("paywallClose")
        }
    }

    @ViewBuilder
    private var offerSection: some View {
        switch store.loadState {
        case .idle, .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text("paywall.loading")
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("paywallOfferLoading")
        case .unavailable:
            VStack(alignment: .leading, spacing: 8) {
                Text("paywall.unavailable")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("paywallOfferUnavailable")
                restoreButton
            }
        case .available:
            if let offer = store.offer {
                VStack(alignment: .leading, spacing: 8) {
                    Button(action: onPurchase) {
                        HStack(spacing: 12) {
                            Text(verbatim: offer.displayName)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Text(verbatim: offer.displayPrice)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WorkshopPalette.purchase)
                    .foregroundStyle(.black)
                    .disabled(store.isPurchasing || store.hasWorkshop)
                    .accessibilityLabel(
                        Text(verbatim: "\(offer.displayName), \(offer.displayPrice)")
                    )
                    .accessibilityHint(Text("paywall.purchase.hint"))
                    .accessibilityIdentifier("paywallPurchase")

                    restoreButton
                }
            }
        }
    }

    private var restoreButton: some View {
        Button(action: onRestore) {
            Text("paywall.restore")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(WorkshopPalette.instrument)
        .disabled(store.isRestoring)
        .accessibilityIdentifier("paywallRestore")
    }

    private var statusKey: LocalizedStringKey? {
        if store.hasWorkshop { return "paywall.status.owned" }
        switch store.lastOutcome {
        case .purchased: return "paywall.status.owned"
        case .pending: return "paywall.status.pending"
        case .cancelled: return "paywall.status.cancelled"
        case .unavailable: return "paywall.status.unavailable"
        case .unverified: return "paywall.status.unverified"
        case .nothingToRestore: return "paywall.status.nothing_to_restore"
        case nil: return nil
        }
    }

    private var termsURL: URL {
        URL(string: WorkshopCatalog.termsOfUseURL) ?? URL(fileURLWithPath: "/")
    }

    private var privacyURL: URL {
        URL(string: WorkshopCatalog.privacyURL) ?? URL(fileURLWithPath: "/")
    }

    /// Same reasoning as the Workshop sheet: the paywall must show its whole
    /// offer without a row clipped at the scroll edge, in every language.
    private var cardWidth: CGFloat {
        min(size.width - 24, max(320, size.width * 0.86))
    }

    /// Width of the decision column, wide enough for the price row and the
    /// two legal links at their 44pt targets.
    private var decisionColumnWidth: CGFloat {
        max(190, (cardWidth - 44) * 0.50)
    }

    /// The modal uses the whole frame it is given: any content row clipped in
    /// half by the scroll edge is reported by the system accessibility audit.
    private var cardHeight: CGFloat {
        max(250, size.height - 24)
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
    static let detailCompactHeightThreshold: CGFloat = 500
    static let detailCompactWidthFraction: CGFloat = 0.47
    static let detailMaximumWidthFraction: CGFloat = 0.50
    static let detailRegularWidthFraction: CGFloat = 0.29
    static let detailMinimumWidth: CGFloat = 210
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
                VStack(alignment: .leading, spacing: usesCompactDetailLayout ? 6 : 10) {
                    Text(step.title)
                        .font(usesCompactDetailLayout ? .headline.bold() : .title3.bold())
                        .accessibilityIdentifier("tableGuideStepTitle")
                    Text(step.body)
                        .font(usesCompactDetailLayout ? .callout : .body)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("tableGuideStepBody")
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
            .accessibilityIdentifier("tableGuideNavigation")
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
            return min(
                size.width - 2 * TableGuideLayoutContract.edgeInset,
                max(
                    TableGuideLayoutContract.controlsMinimumWidth,
                    size.width * TableGuideLayoutContract.controlsWidthFraction
                )
            )
        case .missions, .progress:
            let preferredFraction = usesCompactDetailLayout
                ? TableGuideLayoutContract.detailCompactWidthFraction
                : TableGuideLayoutContract.detailRegularWidthFraction
            return min(
                size.width * TableGuideLayoutContract.detailMaximumWidthFraction,
                max(
                    TableGuideLayoutContract.detailMinimumWidth,
                    size.width * preferredFraction
                )
            )
        }
    }

    private var usesCompactDetailLayout: Bool {
        step != .controls && size.height < TableGuideLayoutContract.detailCompactHeightThreshold
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
