import SwiftUI
import AppIntents

@MainActor enum OneTapRecords {
    struct Session {
        let id = UUID()
        let createdAt = Date()
        let seasonID: UUID
        var deckID: UUID
        var opponentClass: CardClass?
        var opponentID: UUID?
        var first: Bool?
        var won: Bool?
        var saved: Match?
        var error: String?
    }

    static var sessions: [String: Session] = [:]

    static func begin(_ store: Store) throws -> String {
        guard store.loadError == nil else { throw AppError.message(store.loadError ?? "保存先を開けません。") }
        try store.prepareQuickEntry()
        guard let season = store.data.currentSeasonID,
              let deck = store.data.decks.first(where: { $0.id == store.data.lastDeckID && !$0.archived })
                ?? store.data.decks.first(where: { !$0.archived }) else {
            throw AppError.message("高速入力を準備できませんでした。アプリを再起動してください。")
        }
        sessions = sessions.filter { Date().timeIntervalSince($0.value.createdAt) < 8 * 60 * 60 }
        let key = UUID().uuidString
        sessions[key] = Session(seasonID: season, deckID: deck.id)
        return key
    }

    static func cycleDeck(_ key: String, direction: Int, store: Store) throws {
        guard var session = sessions[key] else { throw expired() }
        guard session.saved == nil else { return }
        let decks = store.data.decks.filter { !$0.archived }
        guard !decks.isEmpty else { throw AppError.message("使用できる自分の候補がありません。") }
        let current = decks.firstIndex { $0.id == session.deckID } ?? 0
        session.deckID = decks[(current + direction % decks.count + decks.count) % decks.count].id
        session.error = nil
        sessions[key] = session
    }

    static func selectOpponentClass(_ key: String, cardClass: CardClass) throws {
        guard var session = sessions[key] else { throw expired() }
        guard session.saved == nil else { return }
        session.opponentClass = cardClass
        session.opponentID = nil
        session.error = nil
        sessions[key] = session
    }

    static func selectOpponentArchetype(_ key: String, id: UUID?, store: Store) throws {
        guard var session = sessions[key] else { throw expired() }
        guard session.saved == nil else { return }
        if let id {
            guard store.data.archetypes.contains(where: { $0.id == id && $0.cardClass == session.opponentClass && !$0.archived }) else {
                throw AppError.message("相手の候補が変更されました。選び直してください。")
            }
        }
        session.opponentID = id
        session.error = nil
        sessions[key] = session
    }

    static func selectOutcome(_ key: String, first: Bool, won: Bool) throws {
        guard var session = sessions[key] else { throw expired() }
        guard session.saved == nil else { return }
        session.first = first
        session.won = won
        session.error = nil
        sessions[key] = session
    }

    static func save(_ key: String, store: Store, now: Date = Date()) throws {
        guard var session = sessions[key] else { throw expired() }
        guard session.saved == nil else { return }
        guard let opponentClass = session.opponentClass else { throw AppError.message("相手クラスを選択してください。") }
        guard let first = session.first, let won = session.won else { throw AppError.message("先後と勝敗を選択してください。") }
        guard store.data.decks.contains(where: { $0.id == session.deckID && !$0.archived }),
              store.data.seasons.contains(where: { $0.id == session.seasonID }) else {
            throw AppError.message("入力候補が変更されました。閉じて呼び出し直してください。")
        }
        let match = Match(id: session.id, date: now, seasonID: session.seasonID, deckID: session.deckID,
                          opponentClass: opponentClass, opponentID: session.opponentID,
                          won: won, first: first)
        try store.recordOnce(match)
        session.saved = match
        session.error = nil
        sessions[key] = session
    }

    static func setError(_ error: Error, for key: String) { sessions[key]?.error = error.localizedDescription }

    static func opponentChoices(_ session: Session, data: AppData) -> [Archetype] {
        let standardIDs = Set(AppData.quickDefaults.map { $0.1 })
        return data.archetypes.filter {
            $0.cardClass == session.opponentClass && !$0.archived && !standardIDs.contains($0.id)
        }
    }

    private static func expired() -> AppError {
        AppError.message("入力が終了しました。もう一度ボタンから呼び出してください。")
    }
}

struct OneTapSnippet: SnippetIntent {
    static let title: LocalizedStringResource = "戦績クイック入力"
    static var isDiscoverable: Bool { false }
    @Parameter(title: "入力") var session: String
    init() {}
    init(session: String) { self.session = session }

    @MainActor func perform() async throws -> some IntentResult & ShowsSnippetView {
        guard let value = OneTapRecords.sessions[session] else { throw AppError.message("入力が終了しました。呼び出し直してください。") }
        return .result(view: OneTapView(key: session, session: value, data: Store.shared.data))
    }
}

struct CycleOneTapDeckIntent: AppIntent {
    static let title: LocalizedStringResource = "自分の候補を切り替え"
    static var isDiscoverable: Bool { false }
    static var supportedModes: IntentModes { .background }
    @Parameter(title: "入力") var session: String
    @Parameter(title: "方向") var direction: Int
    init() {}
    init(session: String, direction: Int) { self.session = session; self.direction = direction }
    @MainActor func perform() async throws -> some IntentResult {
        do { try OneTapRecords.cycleDeck(session, direction: direction, store: .shared) }
        catch { OneTapRecords.setError(error, for: session) }
        OneTapSnippet.reload(); return .result()
    }
}

struct SelectOneTapOpponentIntent: AppIntent {
    static let title: LocalizedStringResource = "相手クラスを選択"
    static var isDiscoverable: Bool { false }
    static var supportedModes: IntentModes { .background }
    @Parameter(title: "入力") var session: String
    @Parameter(title: "クラス") var cardClass: String
    init() {}
    init(session: String, cardClass: CardClass) { self.session = session; self.cardClass = cardClass.rawValue }
    @MainActor func perform() async throws -> some IntentResult {
        do {
            guard let value = CardClass(rawValue: cardClass) else { throw AppError.message("クラスが不正です。") }
            try OneTapRecords.selectOpponentClass(session, cardClass: value)
        } catch { OneTapRecords.setError(error, for: session) }
        OneTapSnippet.reload(); return .result()
    }
}

struct SelectOneTapArchetypeIntent: AppIntent {
    static let title: LocalizedStringResource = "相手デッキを選択"
    static var isDiscoverable: Bool { false }
    static var supportedModes: IntentModes { .background }
    @Parameter(title: "入力") var session: String
    @Parameter(title: "相手デッキ") var archetypeID: String
    init() {}
    init(session: String, archetypeID: UUID?) { self.session = session; self.archetypeID = archetypeID?.uuidString ?? "unknown" }
    @MainActor func perform() async throws -> some IntentResult {
        do { try OneTapRecords.selectOpponentArchetype(session, id: UUID(uuidString: archetypeID), store: .shared) }
        catch { OneTapRecords.setError(error, for: session) }
        OneTapSnippet.reload(); return .result()
    }
}

struct SelectOneTapOutcomeIntent: AppIntent {
    static let title: LocalizedStringResource = "勝敗と先後を選択"
    static var isDiscoverable: Bool { false }
    static var supportedModes: IntentModes { .background }
    @Parameter(title: "入力") var session: String
    @Parameter(title: "先攻") var first: Bool
    @Parameter(title: "勝利") var won: Bool
    init() {}
    init(session: String, first: Bool, won: Bool) { self.session = session; self.first = first; self.won = won }
    @MainActor func perform() async throws -> some IntentResult {
        do { try OneTapRecords.selectOutcome(session, first: first, won: won) }
        catch { OneTapRecords.setError(error, for: session) }
        OneTapSnippet.reload(); return .result()
    }
}

struct CommitOneTapIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "戦績を保存"
    static var isDiscoverable: Bool { false }
    static var supportedModes: IntentModes { .background }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    @Parameter(title: "入力") var session: String
    init() {}
    init(session: String) { self.session = session }
    @MainActor func perform() async throws -> some IntentResult {
        do { try OneTapRecords.save(session, store: .shared); await LiveRecords.shared.flush() }
        catch { OneTapRecords.setError(error, for: session) }
        OneTapSnippet.reload(); return .result()
    }
}

struct OneTapView: View {
    let key: String
    let session: OneTapRecords.Session
    let data: AppData
    private let columns = Array(repeating: GridItem(.flexible()), count: 4)

    var body: some View {
        VStack(spacing: 8) {
            Text("⚔️ 戦績クイック入力").font(.headline)
            if session.saved == nil {
                HStack {
                    Button(intent: CycleOneTapDeckIntent(session: key, direction: -1)) { Image(systemName: "chevron.left") }
                    Text("自分  \(data.deckTitle(session.deckID))").font(.subheadline.bold()).frame(maxWidth: .infinity)
                    Button(intent: CycleOneTapDeckIntent(session: key, direction: 1)) { Image(systemName: "chevron.right") }
                }
                Text("相手").font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: columns, spacing: 6) { ForEach(CardClass.allCases) { opponentButton($0) } }
                let choices = OneTapRecords.opponentChoices(session, data: data)
                if !choices.isEmpty {
                    HStack(spacing: 6) {
                        archetypeButton("不明", id: nil)
                        ForEach(choices.prefix(3)) { archetypeButton($0.name, id: $0.id) }
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    outcomeButton("🟢 先攻勝ち", first: true, won: true)
                    outcomeButton("🟢 後攻勝ち", first: false, won: true)
                    outcomeButton("🔴 先攻負け", first: true, won: false)
                    outcomeButton("🔴 後攻負け", first: false, won: false)
                }
            }
            if let error = session.error { Text(error).font(.caption).foregroundStyle(.red) }
            if let saved = session.saved {
                Text("✅ 保存しました  \(saved.date.formatted(date: .omitted, time: .shortened))")
                    .font(.headline).foregroundStyle(.green)
            } else {
                Button(intent: CommitOneTapIntent(session: key)) { Text("保存").fontWeight(.semibold).frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.opponentClass == nil || session.first == nil || session.won == nil)
            }
        }.padding().buttonStyle(.bordered)
    }

    @ViewBuilder private func opponentButton(_ value: CardClass) -> some View {
        let selected = session.opponentClass == value
        if selected {
            Button(intent: SelectOneTapOpponentIntent(session: key, cardClass: value)) {
                Text(data.icon(for: value) + " ✓").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent)
        } else {
            Button(intent: SelectOneTapOpponentIntent(session: key, cardClass: value)) {
                Text(data.icon(for: value)).frame(maxWidth: .infinity)
            }.buttonStyle(.bordered)
        }
    }

    @ViewBuilder private func archetypeButton(_ title: String, id: UUID?) -> some View {
        let selected = session.opponentID == id
        if selected {
            Button(intent: SelectOneTapArchetypeIntent(session: key, archetypeID: id)) {
                Text("✓ " + title).font(.caption).lineLimit(1)
            }.buttonStyle(.borderedProminent)
        } else {
            Button(intent: SelectOneTapArchetypeIntent(session: key, archetypeID: id)) {
                Text(title).font(.caption).lineLimit(1)
            }.buttonStyle(.bordered)
        }
    }

    @ViewBuilder private func outcomeButton(_ title: String, first: Bool, won: Bool) -> some View {
        let selected = session.first == first && session.won == won
        if selected {
            Button(intent: SelectOneTapOutcomeIntent(session: key, first: first, won: won)) {
                Text("✓ " + title).font(.subheadline.bold()).frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).tint(won ? .green : .red)
        } else {
            Button(intent: SelectOneTapOutcomeIntent(session: key, first: first, won: won)) {
                Text(title).font(.subheadline.bold()).frame(maxWidth: .infinity)
            }.buttonStyle(.bordered).tint(won ? .green : .red)
        }
    }
}

struct OneTapPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store
    let sessionKey: String
    @State private var revision = 0
    private let columns = Array(repeating: GridItem(.flexible()), count: 4)
    private var session: OneTapRecords.Session? { _ = revision; return OneTapRecords.sessions[sessionKey] }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let session { content(session).padding() }
                else { ContentUnavailableView("入力が終了しました", systemImage: "exclamationmark.circle") }
            }
            .navigationTitle("高速入力")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
        }
    }

    @ViewBuilder private func content(_ session: OneTapRecords.Session) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if session.saved == nil {
                Text("自分").font(.headline)
                HStack {
                    Button { update { try OneTapRecords.cycleDeck(sessionKey, direction: -1, store: store) } } label: { Image(systemName: "chevron.left") }
                    Text(store.data.deckTitle(session.deckID)).font(.title3.bold()).frame(maxWidth: .infinity)
                    Button { update { try OneTapRecords.cycleDeck(sessionKey, direction: 1, store: store) } } label: { Image(systemName: "chevron.right") }
                }.buttonStyle(.bordered)
                Text("相手").font(.headline)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(CardClass.allCases), id: \.self) { value in opponentClassButton(value, session: session) }
                }
                let choices = OneTapRecords.opponentChoices(session, data: store.data)
                if !choices.isEmpty {
                    Text("相手デッキ（任意）").font(.subheadline.bold())
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                        opponentTypeButton("不明", id: nil, selected: session.opponentID == nil)
                        ForEach(choices) { opponentTypeButton($0.name, id: $0.id, selected: session.opponentID == $0.id) }
                    }
                }
                Text("結果").font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    outcomeButton("🟢 先攻勝ち", first: true, won: true, session: session)
                    outcomeButton("🟢 後攻勝ち", first: false, won: true, session: session)
                    outcomeButton("🔴 先攻負け", first: true, won: false, session: session)
                    outcomeButton("🔴 後攻負け", first: false, won: false, session: session)
                }
            }
            if let error = session.error { Text(error).font(.caption).foregroundStyle(.red) }
            if let saved = session.saved {
                Text("✅ 保存しました").font(.title3.bold()).foregroundStyle(.green)
                Text("\(store.data.deckTitle(saved.deckID)) 対 \(saved.opponentClass.map { store.data.classTitle($0) } ?? "不明")")
                Text("\(saved.first ? "先攻" : "後攻")・\(saved.won ? "勝利" : "敗北")・\(saved.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Button {
                    update {
                        try OneTapRecords.save(sessionKey, store: store)
                        if !ProcessInfo.processInfo.arguments.contains("--ui-testing") { Task { await LiveRecords.shared.flush() } }
                    }
                } label: { Text("保存").font(.headline).frame(maxWidth: .infinity, minHeight: 40) }
                .buttonStyle(.borderedProminent)
                .disabled(session.opponentClass == nil || session.first == nil || session.won == nil)
                Text("日時は保存した時刻を自動で記録します。環境の事前設定は不要です。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func opponentClassButton(_ value: CardClass, session: OneTapRecords.Session) -> some View {
        let selected = session.opponentClass == value
        if selected {
            Button(store.data.icon(for: value) + " ✓") { update { try OneTapRecords.selectOpponentClass(sessionKey, cardClass: value) } }
                .buttonStyle(.borderedProminent).accessibilityLabel(store.data.classTitle(value))
        } else {
            Button(store.data.icon(for: value)) { update { try OneTapRecords.selectOpponentClass(sessionKey, cardClass: value) } }
                .buttonStyle(.bordered).accessibilityLabel(store.data.classTitle(value))
        }
    }

    @ViewBuilder private func opponentTypeButton(_ title: String, id: UUID?, selected: Bool) -> some View {
        if selected {
            Button("✓ " + title) { update { try OneTapRecords.selectOpponentArchetype(sessionKey, id: id, store: store) } }.buttonStyle(.borderedProminent)
        } else {
            Button(title) { update { try OneTapRecords.selectOpponentArchetype(sessionKey, id: id, store: store) } }.buttonStyle(.bordered)
        }
    }

    @ViewBuilder private func outcomeButton(_ title: String, first: Bool, won: Bool, session: OneTapRecords.Session) -> some View {
        let selected = session.first == first && session.won == won
        if selected {
            Button("✓ " + title) { update { try OneTapRecords.selectOutcome(sessionKey, first: first, won: won) } }
                .buttonStyle(.borderedProminent).tint(won ? .green : .red)
        } else {
            Button(title) { update { try OneTapRecords.selectOutcome(sessionKey, first: first, won: won) } }
                .buttonStyle(.bordered).tint(won ? .green : .red)
        }
    }

    private func update(_ operation: () throws -> Void) {
        do { try operation() } catch { OneTapRecords.setError(error, for: sessionKey) }
        revision += 1
    }
}
