import ActivityKit
import WidgetKit
import SwiftUI

struct LiveRecordWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordActivity.self) { context in
            VStack(alignment: .leading, spacing: 6) {
                Text(context.state.deckName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 16) {
                    Text("\(context.state.wins)勝")
                    Text("\(context.state.losses)敗")
                    Text(context.state.rate)
                    if context.state.streak > 1 { Text("\(context.state.streak)連勝").font(.caption) }
                }.font(.subheadline).monospacedDigit()
            }.padding()
                .activityBackgroundTint(.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
                .foregroundStyle(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text("\(context.state.wins)勝").monospacedDigit() }
                DynamicIslandExpandedRegion(.trailing) { Text("\(context.state.losses)敗").monospacedDigit() }
                DynamicIslandExpandedRegion(.center) { Text(context.state.rate).monospacedDigit() }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("\(context.state.deckName) · \(context.state.streak)連勝").font(.caption).lineLimit(1)
                }
            } compactLeading: {
                Text("\(context.state.wins)W").font(.caption2).monospacedDigit()
            } compactTrailing: {
                Text("\(context.state.losses)L").font(.caption2).monospacedDigit()
            } minimal: {
                Text(context.state.wins + context.state.losses == 0 ? "—" : "\(Int((Double(context.state.wins) / Double(context.state.wins + context.state.losses) * 100).rounded()))%")
                    .font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.5).monospacedDigit()
            }
        }
    }
}
