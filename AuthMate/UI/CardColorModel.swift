import SwiftUI

struct CardColorModel {
    static let pastelColors: [Color] = [
        Color(red: 1.0,  green: 0.71, blue: 0.76),  // Rosa cipria
        Color(red: 0.67, green: 0.84, blue: 1.0),   // Azzurro cielo
        Color(red: 0.72, green: 0.93, blue: 0.78),  // Verde menta
        Color(red: 1.0,  green: 0.85, blue: 0.60),  // Giallo pesca
        Color(red: 0.80, green: 0.72, blue: 0.96),  // Lilla
        Color(red: 0.65, green: 0.93, blue: 0.95),  // Turchese chiaro
        Color(red: 1.0,  green: 0.75, blue: 0.60),  // Albicocca
        Color(red: 0.76, green: 0.88, blue: 0.70),  // Salvia
        Color(red: 0.95, green: 0.70, blue: 0.90),  // Orchidea
        Color(red: 0.60, green: 0.80, blue: 0.92),  // Blu fiordaliso
        Color(red: 1.0,  green: 0.93, blue: 0.60),  // Giallo limone
        Color(red: 0.90, green: 0.78, blue: 0.65),  // Cammello chiaro
    ]

    /// Picks a random index different from `lastIndex`
    static func randomIndex(avoiding lastIndex: Int) -> Int {
        let count = pastelColors.count
        guard count > 1 else { return 0 }
        var idx = Int.random(in: 0..<count)
        while idx == lastIndex {
            idx = Int.random(in: 0..<count)
        }
        return idx
    }

    static func color(for index: Int) -> Color {
        let safeIndex = index >= 0 && index < pastelColors.count ? index : 0
        return pastelColors[safeIndex]
    }
}
