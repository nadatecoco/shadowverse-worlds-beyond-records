import AppIntents

enum RecordDestination: String, AppEnum {
    case entry
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "入力画面")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.entry: "戦績入力"]
}

// Included in both targets; OpenIntent routes the foreground action to the containing app.
struct OpenRecordControlIntent: OpenIntent {
    static let title: LocalizedStringResource = "戦績入力"
    static var isDiscoverable: Bool { false }
    static var supportedModes: IntentModes { .foreground }
    @Parameter(title: "画面") var target: RecordDestination
    init() { target = .entry }
    @MainActor func perform() async throws -> some IntentResult {
        #if !CONTROL_EXTENSION
        Store.shared.showQuickEntry = true
        #endif
        return .result()
    }
}
