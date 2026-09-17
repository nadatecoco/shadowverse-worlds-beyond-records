import ActivityKit
import Foundation

struct RecordActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var deckName: String
        var seasonName: String
        var wins: Int
        var losses: Int
        var streak: Int
        var rate: String {
            let total = wins + losses
            return total == 0 ? "—" : String(format: "%.1f%%", Double(wins) / Double(total) * 100)
        }
    }
    var label: String = "ライブ戦績"
}
