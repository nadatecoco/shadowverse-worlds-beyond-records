import SwiftUI
import WidgetKit
import AppIntents

@main struct RecordControlBundle: WidgetBundle {
    var body: some Widget { RecordInputControl(); LiveRecordWidget() }
}
struct RecordInputControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "blog.epiclog.shadowrecord.input") {
            ControlWidgetButton(action: OpenRecordControlIntent()) {
                Label("戦績入力", systemImage: "square.and.pencil")
            }
        }
        .displayName("戦績入力")
        .description("アプリを開いて戦績を入力します。小さい入力画面はAction Buttonの「戦績を記録」を選んでください。")
    }
}
