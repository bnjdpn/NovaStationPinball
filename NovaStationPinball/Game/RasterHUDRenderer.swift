import NovaStationCore
import UIKit

@MainActor
struct RasterHUDRenderer {
    struct Content: Equatable {
        let score: Int
        let ballsRemaining: Int
        let ballsInPlay: Int
        let mission: MissionState
        let clearance: ClearanceLevel?
        let scoreMultiplier: Int
        let bonusMultiplier: Int
        let stationPower: Int
        let isTilted: Bool
        let phase: GameSessionPhase
        let status: String
    }

    private let canvasSize = CGSize(width: 412, height: 608)

    func image(for content: Content) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        format.scale = 1
        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { _ in
            UIImage(named: "hud-overlay")?.draw(in: CGRect(origin: .zero, size: canvasSize))
            draw(lines(for: content))
        }
    }

    private func draw(_ lines: [(String, UIColor, CGFloat)]) {
        var y: CGFloat = 94
        for (text, color, fontSize) in lines {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byTruncatingTail
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: color,
                .paragraphStyle: paragraph,
                .kern: 0.8
            ]
            (text as NSString).draw(
                in: CGRect(x: 34, y: y, width: canvasSize.width - 68, height: fontSize * 1.45),
                withAttributes: attributes
            )
            y += fontSize * 1.65
        }
    }

    private func lines(for content: Content) -> [(String, UIColor, CGFloat)] {
        let cyan = UIColor(red: 0.46, green: 0.96, blue: 0.96, alpha: 1)
        let amber = UIColor(red: 1.0, green: 0.78, blue: 0.30, alpha: 1)
        let coral = UIColor(red: 1.0, green: 0.38, blue: 0.34, alpha: 1)
        let mission = missionText(content.mission)
        let clearance = content.clearance.map { clearanceText($0) }
            ?? String(localized: "hud.clearance.none")
        let phaseLine: String = switch content.phase {
        case .launch: String(localized: "hud.phase.launch")
        case .playing: content.status
        case .gameOver: String(localized: "hud.phase.game_over")
        }
        let alertColor = content.isTilted || content.phase == .gameOver ? coral : amber

        return [
            (String.localizedStringWithFormat(String(localized: "hud.score"), Int64(content.score)), cyan, 34),
            (String.localizedStringWithFormat(
                String(localized: "hud.balls"),
                Int64(content.ballsRemaining),
                Int64(content.ballsInPlay)
            ), amber, 20),
            (mission, cyan, 19),
            (clearance, amber, 18),
            (String.localizedStringWithFormat(
                String(localized: "hud.multipliers"),
                Int64(content.scoreMultiplier),
                Int64(content.bonusMultiplier)
            ), cyan, 17),
            (String.localizedStringWithFormat(
                String(localized: "hud.station_power"),
                Int64(content.stationPower)
            ), amber, 17),
            (content.isTilted ? String(localized: "hud.tilt") : phaseLine, alertColor, 20)
        ]
    }

    private func missionText(_ state: MissionState) -> String {
        switch state {
        case .idle:
            return String(localized: "hud.mission.idle")
        case .active(let id):
            return String.localizedStringWithFormat(
                String(localized: "hud.mission.active"),
                localizedMission(id)
            )
        case .completed(let id):
            return String.localizedStringWithFormat(
                String(localized: "hud.mission.completed"),
                localizedMission(id)
            )
        case .failed(let id):
            return String.localizedStringWithFormat(
                String(localized: "hud.mission.failed"),
                localizedMission(id)
            )
        }
    }

    private func localizedMission(_ id: MissionID) -> String {
        String(localized: String.LocalizationValue("mission.\(id.rawValue)"))
    }

    private func clearanceText(_ clearance: ClearanceLevel) -> String {
        String.localizedStringWithFormat(
            String(localized: "hud.clearance"),
            String(localized: String.LocalizationValue("clearance.\(clearance.rawValue)"))
        )
    }
}
