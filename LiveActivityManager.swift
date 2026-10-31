import Foundation

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

/// Lance / termine l'activité en direct (Dynamic Island + écran verrouillé) pour un bus choisi dans la page.
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    func start(_ body: Any) {
        guard let d = body as? [String: Any],
              let stop = d["stop"] as? String,
              let line = d["line"] as? String,
              let ms = d["dep"] as? Double,
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let departure = Date(timeIntervalSince1970: ms / 1000)
        let attrs = BusActivityAttributes(
            stop: stop,
            arrivalStop: d["arrStop"] as? String ?? "",
            line: line,
            colorHex: d["color"] as? String ?? "555555",
            headsign: d["head"] as? String ?? "",
            departureText: d["depT"] as? String ?? "")
        let state = BusActivityAttributes.ContentState(
            departure: departure,
            arrivalText: d["arrT"] as? String ?? "")

        Task {
            for a in Activity<BusActivityAttributes>.activities {
                await a.end(nil, dismissalPolicy: .immediate)
            }
            let content = ActivityContent(state: state, staleDate: departure.addingTimeInterval(120))
            _ = try? Activity.request(attributes: attrs, content: content, pushType: nil)
        }
    }

    /// Ferme les suivis dont le bus est déjà parti.
    func endExpired() {
        Task {
            for a in Activity<BusActivityAttributes>.activities
            where a.content.state.departure < Date().addingTimeInterval(-120) {
                await a.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
#else
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    func start(_ body: Any) {}
    func endExpired() {}
}
#endif
