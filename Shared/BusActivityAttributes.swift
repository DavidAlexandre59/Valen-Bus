// Ce fichier doit appartenir aux DEUX cibles : l'app ET l'extension BusWidget.
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

struct BusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var departure: Date        // heure de départ du bus à l'arrêt
        var arrivalText: String    // heure d'arrivée à l'arrêt choisi ("15h52"), vide si aucun
    }
    var stop: String               // arrêt de départ
    var arrivalStop: String        // arrêt d'arrivée (facultatif)
    var line: String               // T1, T2, 5...
    var colorHex: String           // couleur de la ligne
    var headsign: String           // direction
    var departureText: String      // "15h45"
}
#endif
