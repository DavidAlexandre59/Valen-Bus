// Fichier de l'extension "BusWidget" (Widget Extension avec Live Activity).
import ActivityKit
import SwiftUI
import WidgetKit

@main
struct BusWidgetBundle: WidgetBundle {
    var body: some Widget { BusLiveActivity() }
}

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
}

struct LineBadge: View {
    let line: String
    let hex: String
    var body: some View {
        Text(line)
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Color(hex: hex), in: RoundedRectangle(cornerRadius: 7))
    }
}

/// Compte à rebours qui avance tout seul jusqu'au départ (s'arrête à 0:00).
struct Countdown: View {
    let departure: Date
    var body: some View {
        Text(timerInterval: Date.now...max(departure, Date.now), countsDown: true)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
    }
}

func detailLine(_ c: ActivityViewContext<BusActivityAttributes>) -> String {
    var t = "Départ \(c.attributes.departureText)"
    if !c.state.arrivalText.isEmpty {
        t += " · arrivée \(c.state.arrivalText)"
        if !c.attributes.arrivalStop.isEmpty { t += " à \(c.attributes.arrivalStop)" }
    }
    return t
}

struct LockView: View {
    let context: ActivityViewContext<BusActivityAttributes>
    var body: some View {
        HStack(spacing: 12) {
            LineBadge(line: context.attributes.line, hex: context.attributes.colorHex)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.stop).font(.headline).lineLimit(1)
                Text(detailLine(context)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Countdown(departure: context.state.departure).font(.system(size: 34, weight: .bold))
                Text("avant le départ").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

struct BusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BusActivityAttributes.self) { context in
            LockView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LineBadge(line: context.attributes.line, hex: context.attributes.colorHex)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(departure: context.state.departure).font(.title2.bold()).frame(width: 90)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.stop).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(detailLine(context)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            } compactLeading: {
                LineBadge(line: context.attributes.line, hex: context.attributes.colorHex)
            } compactTrailing: {
                Countdown(departure: context.state.departure).frame(width: 46)
            } minimal: {
                Text(context.attributes.line).font(.caption.bold())
            }
        }
    }
}
