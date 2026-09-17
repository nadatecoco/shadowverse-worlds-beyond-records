import SwiftUI
import AppIntents

@main struct ShadowRecordApp: App {
    @State private var store: Store
    init() {
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let instance = testing ? Store(inMemory: true) : Store.shared
        if testing {
            instance.addExamples()
            instance.perform { data in
                let sampleNames = ["ダストデイズエルフ", "魔手ウィッチ"]
                for name in sampleNames {
                    if let archetype = data.archetypes.first(where: { $0.name == name }), !data.decks.contains(where: { $0.name == name }) {
                        data.decks.append(Deck(name: name, archetypeID: archetype.id))
                    }
                }
                let samples = data.decks.filter { sampleNames.contains($0.name) }
                data.activeDeckID = samples.first?.id
                for (row, deck) in samples.enumerated() {
                    for (col, opponent) in data.archetypes.filter({ sampleNames.contains($0.name) }).enumerated() {
                        data.opinions.append(Opinion(scope: data.currentSeasonID!.uuidString, deckID: deck.id, opponentID: opponent.id, percent: [[50.0, 55.0], [35.0, 60.0]][row][col]))
                    }
                }
            }
        }
        _store = State(initialValue: instance)
        RecordShortcuts.updateAppShortcutParameters()
    }
    var body: some Scene {
        WindowGroup { RootView().environment(store) }
    }
}
struct RootView: View {
    @Environment(Store.self) private var store
    @State private var scope = ""
    var body: some View {
        @Bindable var store = store
        Group {
            if let error = store.loadError {
                ContentUnavailableView("データを開けません", systemImage: "externaldrive.badge.exclamationmark", description: Text(error + "\nデータは初期化していません。アプリを再起動してください。"))
            } else {
                TabView {
                    Tab("戦績", systemImage: "list.bullet.rectangle") { NavigationStack { HistoryView(scope: $scope) } }
                    Tab("相性表", systemImage: "tablecells") { NavigationStack { MatrixView(scope: $scope) } }
                    Tab("持ち込み", systemImage: "rectangle.split.2x2") { NavigationStack { LineupView(scope: $scope) } }
                    Tab("デッキ／設定", systemImage: "slider.horizontal.3") { NavigationStack { SettingsView(scope: $scope) } }
                }
            }
        }
        .onAppear { if scope.isEmpty { scope = store.data.currentSeasonID?.uuidString ?? "all" } }
        .onChange(of: store.data.currentSeasonID) { old, new in
            if scope == old?.uuidString { scope = new?.uuidString ?? "all" }
        }
        .onChange(of: store.data.seasons) { _, seasons in
            if scope != "all", !seasons.contains(where: { $0.id.uuidString == scope }) { scope = store.data.currentSeasonID?.uuidString ?? "all" }
        }
        .sheet(isPresented: $store.showQuickEntry) { QuickEntryView() }
        .alert("操作を完了できません", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("閉じる", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}
struct ScopePicker: View {
    @Environment(Store.self) private var store
    @Binding var scope: String
    var body: some View {
        Picker("集計環境", selection: $scope) {
            ForEach(store.data.seasons) { season in
                Text((season.id == store.data.currentSeasonID ? "現在：" : "") + season.name).tag(season.id.uuidString)
            }
            Text("全期間").tag("all")
        }
    }
}
struct StatsView: View {
    let stats: Stats
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if stats.count > 0 && stats.count < 10 { Text(stats.sample).font(.subheadline.bold()).foregroundStyle(.secondary) }
            Text(stats.count == 0 ? "未対戦" : percentage(stats.rate)).font(stats.count < 10 ? .headline : .title2.bold()).monospacedDigit()
            Text("\(stats.wins)勝\(stats.losses)敗 / \(stats.count)戦 ・ \(stats.sample)").font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
struct HistoryView: View {
    @Environment(Store.self) private var store
    @Binding var scope: String
    @State private var deckID: UUID?
    @State private var editing: Match?
    @State private var deleting: Match?
    @State private var grouping = 0
    @State private var oneTapPreview: OneTapPreviewSession?
    private var matches: [Match] { store.data.filtered(scope, deckID: deckID).sorted { $0.date > $1.date } }
    var body: some View {
        List {
            Section {
                Button {
                    do {
                        oneTapPreview = OneTapPreviewSession(id: try OneTapRecords.begin(store))
                    } catch {
                        store.error = error.localizedDescription
                    }
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("⚡ 高速入力を試す").font(.headline)
                            Text("自分・相手・結果を選んで保存").font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "bolt.fill").font(.title2).foregroundStyle(.yellow)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("高速入力を試す")
                NavigationLink { InputSetupView() } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("⚡ 高速入力を設定").font(.headline)
                            Text("ボタンからすぐに戦績を記録").font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "bolt.circle.fill").font(.title2).foregroundStyle(.blue) }
                }
            }
            LiveRecordSettings()
            Section {
                ScopePicker(scope: $scope)
                Picker("自分のデッキ", selection: $deckID) {
                    Text("すべて").tag(nil as UUID?)
                    ForEach(store.data.decks) { Text(store.data.deckTitle($0.id)).tag(Optional($0.id)) }
                }
                StatsView(stats: Stats(matches))
            }
            Section("集計") {
                Picker("集計軸", selection: $grouping) { Text("クラス").tag(0); Text("タイプ×先後").tag(1); Text("先後").tag(2) }.pickerStyle(.segmented)
                if grouping == 0 {
                    ForEach(CardClass.allCases) { cardClass in
                        let stats = Stats(matches.filter { $0.opponentClass == cardClass })
                        HStack { Text(store.data.classTitle(cardClass)); Spacer(); Text("\(percentage(stats.rate))  \(stats.wins)-\(stats.losses)").monospacedDigit() }
                    }
                } else if grouping == 1 {
                    ForEach(store.data.archetypes.filter { archetype in matches.contains { $0.opponentID == archetype.id } }) { archetype in
                        let stats = Stats(matches.filter { $0.opponentID == archetype.id })
                        VStack(alignment: .leading) {
                            Text(archetype.name).font(.headline)
                            Text("\(percentage(stats.rate)) ・ \(stats.wins)勝\(stats.losses)敗 ・ \(stats.sample)")
                            Text("先攻 \(percentage(Stats(matches.filter { $0.opponentID == archetype.id && $0.first }).rate)) (\(stats.firstWins)-\(stats.firstLosses))\n後攻 \(percentage(Stats(matches.filter { $0.opponentID == archetype.id && !$0.first }).rate)) (\(stats.secondWins)-\(stats.secondLosses))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    let unknown = Stats(matches.filter { $0.opponentID == nil })
                    if unknown.count > 0 { VStack(alignment: .leading) { Text("アーキタイプ不明"); StatsView(stats: unknown) } }
                } else {
                    VStack(alignment: .leading) { Text("先攻"); StatsView(stats: Stats(matches.filter(\.first))) }
                    VStack(alignment: .leading) { Text("後攻"); StatsView(stats: Stats(matches.filter { !$0.first })) }
                }
            }
            Section("履歴（\(matches.count)戦）") {
                if matches.isEmpty { Text("右上の＋、またはAction Buttonから記録できます。").foregroundStyle(.secondary) }
                ForEach(matches) { match in
                    Button { editing = match } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text(match.won ? "勝利" : "敗北").foregroundStyle(match.won ? .green : .secondary); Text(match.first ? "先攻" : "後攻"); Spacer(); Text(match.date, format: .dateTime.month().day().hour().minute()).font(.caption) }
                            Text(store.data.deckTitle(match.deckID)).font(.headline)
                            Text("対 \(match.opponentClass.map { store.data.classTitle($0) } ?? "相手不明") / \(store.data.archetypeName(match.opponentID))").font(.subheadline)
                            if !match.note.isEmpty { Text(match.note).font(.caption).lineLimit(2) }
                        }.foregroundStyle(.primary)
                    }
                    .swipeActions { Button("削除", role: .destructive) { deleting = match } }
                }
            }
        }
        .navigationTitle("戦績")
        .toolbar { Button("戦績を追加", systemImage: "plus") { store.showQuickEntry = true } }
        .sheet(item: $editing) { MatchEditor(existing: $0) }
        .sheet(item: $oneTapPreview) { preview in
            OneTapPreviewView(sessionKey: preview.id)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("この戦績を削除しますか？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("削除", role: .destructive) { if let deleting { store.perform { $0.matches.removeAll { $0.id == deleting.id } } }; deleting = nil }
        }
    }
}
struct OneTapPreviewSession: Identifiable {
    let id: String
}
struct MatchEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    var existing: Match?
    @State private var id = UUID()
    @State private var deckID: UUID?
    @State private var seasonID: UUID?
    @State private var opponentClass: CardClass? = nil
    @State private var opponentID: UUID?
    @State private var result: Int?
    @State private var date = Date()
    @State private var note = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("環境", selection: $seasonID) { ForEach(store.data.seasons) { Text($0.name).tag(Optional($0.id)) } }
                    Picker("自分のデッキ", selection: $deckID) {
                        Text("選択してください").tag(nil as UUID?)
                        ForEach(store.data.decks.filter { !$0.archived || $0.id == existing?.deckID }) { Text(store.data.deckTitle($0.id)).tag(Optional($0.id)) }
                    }
                    if store.data.decks.isEmpty { Text("先に「デッキ／設定」で自分のデッキを登録してください。").foregroundStyle(.secondary) }
                }
                Section("相手") {
                    Picker("クラス", selection: $opponentClass) { Text("不明").tag(nil as CardClass?); ForEach(CardClass.allCases) { Text(store.data.classTitle($0)).tag(Optional($0)) } }
                    Picker("アーキタイプ", selection: $opponentID) {
                        Text("不明").tag(nil as UUID?)
                        ForEach(store.data.archetypes.filter { $0.cardClass == opponentClass && !store.data.isQuickDefaultArchetype($0.id) && (!$0.archived || $0.id == existing?.opponentID) }) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Section("勝敗・先後") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                        ForEach(0..<4) { index in
                            Button(resultTitle(index)) { result = index }
                                .buttonStyle(.bordered).tint(result == index ? .blue : .gray)
                                .accessibilityAddTraits(result == index ? .isSelected : [])
                        }
                    }
                }
                Section("詳細") { DatePicker("日時", selection: $date); TextField("メモ（任意）", text: $note, axis: .vertical) }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(existing == nil ? "戦績を記録" : "戦績を修正")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.disabled(deckID == nil || seasonID == nil || result == nil) }
            }
            .onAppear {
                if let existing { id = existing.id; deckID = existing.deckID; seasonID = existing.seasonID; opponentClass = existing.opponentClass; opponentID = existing.opponentID; result = (existing.first ? 0 : 2) + (existing.won ? 0 : 1); date = existing.date; note = existing.note }
                else { deckID = store.data.decks.first { $0.id == store.data.lastDeckID && !$0.archived }?.id ?? store.data.decks.first { !$0.archived }?.id; seasonID = store.data.currentSeasonID }
            }
            .onChange(of: opponentClass) { _, newValue in
                if let opponentID, !store.data.archetypes.contains(where: { $0.id == opponentID && $0.cardClass == newValue }) { self.opponentID = nil }
            }
        }
    }
    private func save() {
        guard let deckID, let seasonID, let result else { return }
        let match = Match(id: id, date: date, seasonID: seasonID, deckID: deckID, opponentClass: opponentClass, opponentID: opponentID, won: result % 2 == 0, first: result < 2, note: note)
        do { try store.saveMatch(match); dismiss() } catch { self.error = error.localizedDescription }
    }
}
func resultTitle(_ index: Int) -> String { ["先攻勝利", "先攻敗北", "後攻勝利", "後攻敗北"][max(0, min(index, 3))] }
