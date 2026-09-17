import AppIntents
import SwiftUI

struct QuickDraft: Sendable {
    let id: UUID
    var deckID: UUID
    let seasonID: UUID
    var cardClass: CardClass?
    var opponentID: UUID?
    var opponentChosen = false
    var result: Int?
    var stage = 0
    var page = 0
    var message: String?
}
@MainActor enum QuickSessions {
    static var drafts: [String: QuickDraft] = [:]
    static func begin(store: Store) throws -> String {
        guard store.loadError == nil else { throw AppError.message(store.loadError!) }
        guard let season = store.data.currentSeasonID,
              let deck = store.data.decks.first(where: { $0.id == store.data.lastDeckID && !$0.archived }) ?? store.data.decks.first(where: { !$0.archived }) else {
            throw AppError.message("先にアプリを開き、自分のデッキと現在環境を設定してください。")
        }
        let id = UUID(); let key = id.uuidString
        drafts[key] = QuickDraft(id: id, deckID: deck.id, seasonID: season)
        return key
    }
    static func match(_ key: String, store: Store) throws -> Match {
        guard let draft = drafts[key], let cardClass = draft.cardClass, draft.opponentChosen, let result = draft.result else {
            throw AppError.message("相手クラス、アーキタイプ、勝敗・先後を選択してください。")
        }
        guard store.data.decks.contains(where: { $0.id == draft.deckID && !$0.archived }), store.data.seasons.contains(where: { $0.id == draft.seasonID }) else {
            throw AppError.message("デッキまたは環境が変更されました。一度閉じてやり直してください。")
        }
        return Match(id: draft.id, seasonID: draft.seasonID, deckID: draft.deckID, opponentClass: cardClass, opponentID: draft.opponentID, won: result % 2 == 0, first: result < 2)
    }
}
struct RecordMatchIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "戦績を記録"
    static let description = IntentDescription("自分と相手、勝敗・先後を選んで戦績を記録します。事前設定は不要です。")
    static var supportedModes: IntentModes { .background }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    @MainActor func perform() async throws -> some IntentResult & ShowsSnippetIntent {
        let key = try OneTapRecords.begin(Store.shared)
        return .result(snippetIntent: OneTapSnippet(session: key))
    }
}
struct RecordSnippet: SnippetIntent {
    static let title: LocalizedStringResource = "戦績入力"
    static var isDiscoverable: Bool { false }
    @Parameter(title: "入力セッション") var session: String
    init() {}
    init(session: String) { self.session = session }
    @MainActor func perform() async throws -> some IntentResult & ShowsSnippetView {
        guard let draft = QuickSessions.drafts[session] else { throw AppError.message("入力が終了しました。もう一度呼び出してください。") }
        return .result(view: QuickSnippetView(session: session, draft: draft, data: Store.shared.data))
    }
}
struct UpdateQuickInput: AppIntent {
    static let title: LocalizedStringResource = "入力を選択"
    static var isDiscoverable: Bool { false }
    static var supportedModes: IntentModes { .background }
    @Parameter(title: "入力セッション") var session: String
    @Parameter(title: "操作") var operation: String
    @Parameter(title: "値") var value: String
    init() {}
    init(session: String, operation: String, value: String) { self.session = session; self.operation = operation; self.value = value }
    @MainActor func perform() async throws -> some IntentResult {
        guard var draft = QuickSessions.drafts[session] else { throw AppError.message("入力が終了しました。") }
        draft.message = nil
        switch operation {
        case "class":
            guard let cardClass = CardClass(rawValue: value) else { throw AppError.message("クラスが不正です。") }
            draft.cardClass = cardClass; draft.opponentID = nil; draft.result = nil
            let hasChoices = Store.shared.data.archetypes.contains { $0.cardClass == cardClass && !$0.archived && !Store.shared.data.isQuickDefaultArchetype($0.id) }
            draft.opponentChosen = !hasChoices; draft.stage = hasChoices ? 1 : 2; draft.page = 0
        case "archetype":
            if value == "unknown" { draft.opponentID = nil }
            else {
                guard let id = UUID(uuidString: value), Store.shared.data.archetypes.contains(where: { $0.id == id && $0.cardClass == draft.cardClass && !$0.archived }) else { throw AppError.message("候補が変更されました。相手クラスを選び直してください。") }
                draft.opponentID = id
            }
            draft.opponentChosen = true; draft.stage = 2; draft.page = 0
        case "result":
            guard let result = Int(value), (0...3).contains(result) else { throw AppError.message("勝敗が不正です。") }
            draft.result = result; draft.stage = 3
        case "stage": draft.stage = Int(value) ?? 0; draft.page = 0
        case "page": draft.page = max(0, Int(value) ?? 0)
        case "deck":
            guard let id = UUID(uuidString: value), Store.shared.data.decks.contains(where: { $0.id == id && !$0.archived }) else { throw AppError.message("デッキが見つかりません。") }
            draft.deckID = id; draft.stage = draft.result == nil ? (draft.opponentChosen ? 2 : (draft.cardClass == nil ? 0 : 1)) : 3; draft.page = 0
        default: throw AppError.message("操作が不正です。")
        }
        QuickSessions.drafts[session] = draft
        return .result()
    }
}
struct QuickSnippetView: View {
    let session: String; let draft: QuickDraft; let data: AppData
    private var choices: [Archetype] {
        let lastUsed = Dictionary(grouping: data.matches, by: \.opponentID).mapValues { $0.map(\.date).max() ?? .distantPast }
        return data.archetypes.filter { $0.cardClass == draft.cardClass && !$0.archived && !data.isQuickDefaultArchetype($0.id) }.sorted {
            let left = lastUsed[Optional($0.id)] ?? .distantPast, right = lastUsed[Optional($1.id)] ?? .distantPast
            return left == right ? $0.name < $1.name : left > right
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(data.seasonName(draft.seasonID)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                action(data.deckName(draft.deckID), "stage", "4")
            }
            if let message = draft.message { Text(message).font(.caption).foregroundStyle(.red) }
            switch draft.stage {
            case 0:
                Text("相手クラス").font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                    ForEach(CardClass.allCases) { action(data.classTitle($0), "class", $0.rawValue) }
                }
            case 1:
                Text(draft.cardClass.map { data.classTitle($0) } ?? "相手").font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                    ForEach(Array(choices.dropFirst(draft.page * 4).prefix(4))) { action($0.name, "archetype", $0.id.uuidString) }
                    action("不明", "archetype", "unknown")
                }
                HStack {
                    action("クラスを戻る", "stage", "0")
                    if draft.page > 0 { action("前", "page", String(draft.page - 1)) }
                    if choices.count > (draft.page + 1) * 4 { action("次", "page", String(draft.page + 1)) }
                }.font(.caption)
            case 2:
                Text("\(draft.cardClass.map { data.classTitle($0) } ?? "") / \(data.archetypeName(draft.opponentID))").font(.caption)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                    ForEach(0..<4) { action(resultTitle($0), "result", String($0)) }
                }
                action("相手を選び直す", "stage", "0").font(.caption)
            case 4:
                Text("自分のデッキ").font(.headline)
                let decks = data.decks.filter { !$0.archived }
                ForEach(Array(decks.dropFirst(draft.page * 3).prefix(3))) { action($0.name, "deck", $0.id.uuidString) }
                HStack {
                    if draft.page > 0 { action("前", "page", String(draft.page - 1)) }
                    if decks.count > (draft.page + 1) * 3 { action("次", "page", String(draft.page + 1)) }
                }
            default:
                Text(resultTitle(draft.result ?? 0)).font(.title2.bold())
                Text("対 \(draft.cardClass.map { data.classTitle($0) } ?? "") / \(data.archetypeName(draft.opponentID))")
                Text("下の「保存」で記録します。").font(.caption).foregroundStyle(.secondary)
                HStack { action("相手を修正", "stage", "0"); action("勝敗を修正", "stage", "2") }.font(.caption)
            }
        }.padding().buttonStyle(.bordered)
    }
    private func action(_ title: String, _ operation: String, _ value: String) -> some View {
        Button(intent: UpdateQuickInput(session: session, operation: operation, value: value)) { Text(title).frame(maxWidth: .infinity).lineLimit(2) }
    }
}
struct RecordShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RecordMatchIntent(), phrases: ["\(.applicationName)で戦績を記録"], shortTitle: "戦績を記録", systemImageName: "plus.circle")
    }
}
