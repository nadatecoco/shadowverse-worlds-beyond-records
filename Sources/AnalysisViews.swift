import SwiftUI

struct CellSelection: Identifiable { var id: String { "\(deck)/\(opponent)" }; var deck: UUID; var opponent: UUID }
struct MatrixView: View {
    @Environment(Store.self) private var store
    @Binding var scope: String
    @State private var mode = 2
    @State private var cardClass: CardClass?
    @State private var selected: CellSelection?
    private var opponents: [Archetype] { store.data.archetypes.filter { !$0.archived && !store.data.isQuickDefaultArchetype($0.id) && (cardClass == nil || $0.cardClass == cardClass) } }
    var body: some View {
        VStack(spacing: 12) {
            VStack {
                ScopePicker(scope: $scope)
                Picker("表示", selection: $mode) { Text("🧠 主観").tag(0); Text("📊 実戦").tag(1); Text("両方").tag(2) }.pickerStyle(.segmented)
                Picker("相手クラス", selection: $cardClass) { Text("全クラス").tag(nil as CardClass?); ForEach(CardClass.allCases) { Text(store.data.classTitle($0)).tag(Optional($0)) } }
            }.padding(.horizontal)
            if store.data.decks.filter({ !$0.archived }).isEmpty || opponents.isEmpty {
                ContentUnavailableView("デッキとアーキタイプを登録", systemImage: "tablecells", description: Text("「デッキ／設定」で登録すると相性表が表示されます。"))
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Grid(alignment: .topLeading, horizontalSpacing: 1, verticalSpacing: 1) {
                        GridRow {
                            Text("自分 ↓ / 相手 →").font(.caption).frame(width: 120)
                            ForEach(opponents) { Text($0.name).font(.subheadline.bold()).frame(width: 160).frame(minHeight: 44) }
                        }
                        ForEach(store.data.decks.filter { !$0.archived }) { deck in
                            GridRow {
                                Text(deck.name).font(.headline).frame(width: 120, alignment: .leading).padding(.vertical, 12)
                                ForEach(opponents) { opponent in
                                    Button { selected = CellSelection(deck: deck.id, opponent: opponent.id) } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("\(deck.name) → \(opponent.name)").font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                            if mode != 1 {
                                                let value = Analysis.value(data: store.data, scope: scope, deck: deck.id, opponent: .archetype(opponent.id), source: .opinion)
                                                Text("🧠 " + (value.percent == nil ? "未設定" : percentage(value.percent)))
                                            }
                                            if mode != 0 {
                                                let value = Analysis.value(data: store.data, scope: scope, deck: deck.id, opponent: .archetype(opponent.id), source: .actual)
                                                Text("📊 " + (value.percent == nil ? "未対戦" : percentage(value.percent)))
                                                Text("\(value.sampleCount ?? 0)戦 ・ \(Stats.sample(value.sampleCount ?? 0))").font(.caption2).foregroundStyle(.secondary)
                                            }
                                        }.frame(width: 144, alignment: .leading).padding(8).frame(maxHeight: .infinity).background(.quaternary.opacity(0.5))
                                    }.buttonStyle(.plain).accessibilityLabel("\(deck.name) 対 \(opponent.name)")
                                }
                            }
                        }
                    }.padding(.horizontal)
                }.defaultScrollAnchor(.topLeading)
            }
            Text(scope == "all" ? "全期間の主観値は独立した評価です。セルをタップして編集。" : "セルをタップして主観値・先後別成績を確認。").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
        }
        .navigationTitle("相性表")
        .sheet(item: $selected) { OpinionEditor(scope: scope, selection: $0) }
    }
}
struct OpinionEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let scope: String; let selection: CellSelection
    @State private var percent = 50.0
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(store.data.deckName(selection.deck)); Text("対 " + store.data.archetypeName(selection.opponent)) }
                Section("🧠 自分の評価") {
                    Stepper("\(Int(percent))%", value: $percent, in: 0...100, step: 1)
                    Slider(value: $percent, in: 0...100, step: 1).accessibilityLabel("主観相性")
                    Text("保存するまで主観値は変更されません。").font(.caption).foregroundStyle(.secondary)
                    Button("主観値を未設定に戻す", role: .destructive) {
                        do { try store.commit { $0.opinions.removeAll { $0.scope == scope && $0.deckID == selection.deck && $0.opponentID == selection.opponent } }; dismiss() } catch { self.error = error.localizedDescription }
                    }
                }
                Section("📊 実戦値") {
                    let stats = Stats(store.data.filtered(scope, deckID: selection.deck).filter { $0.opponentID == selection.opponent })
                    StatsView(stats: stats)
                    Text("先攻：\(stats.firstWins)勝\(stats.firstLosses)敗")
                    Text("後攻：\(stats.secondWins)勝\(stats.secondLosses)敗")
                    Text("件数の目安：1〜9戦は少、10〜29戦は中程度、30戦以上は十分。勝率の精度を保証する指標ではありません。").font(.caption).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("相性の詳細")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") {
                        do { try store.commit { data in
                            data.opinions.removeAll { $0.scope == scope && $0.deckID == selection.deck && $0.opponentID == selection.opponent }
                            data.opinions.append(Opinion(scope: scope, deckID: selection.deck, opponentID: selection.opponent, percent: percent))
                        }; dismiss() } catch { self.error = error.localizedDescription }
                    } }
                }
                .onAppear { percent = store.data.opinions.first { $0.scope == scope && $0.deckID == selection.deck && $0.opponentID == selection.opponent }?.percent ?? 50 }
        }
    }
}
struct LineupView: View {
    @Environment(Store.self) private var store
    @Binding var scope: String
    @State private var firstDeck: UUID?
    @State private var secondDeck: UUID?
    @State private var opponent1 = ""
    @State private var opponent2 = ""
    @State private var source = ValueSource.opinion
    private func opponent(_ key: String) -> Opponent? {
        if let cardClass = CardClass(rawValue: key) { return .cardClass(cardClass) }
        if let id = UUID(uuidString: key), store.data.archetypes.contains(where: { $0.id == id }) { return .archetype(id) }; return nil
    }
    private func name(_ key: String) -> String { CardClass(rawValue: key).map { store.data.classTitle($0) } ?? store.data.archetypeName(UUID(uuidString: key)) }
    var body: some View {
        Form {
            Section { ScopePicker(scope: $scope); Picker("使用する値", selection: $source) { ForEach(ValueSource.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented) }
            Section("比較するデッキ") {
                if firstDeck != nil && secondDeck != nil && firstDeck != secondDeck && opponent(opponent1) != nil && opponent(opponent2) != nil {
                    DisclosureGroup("選択を変更") { selectionFields }
                } else { selectionFields }
            }
            if let firstDeck, let secondDeck, firstDeck != secondDeck, let a = opponent(opponent1), let b = opponent(opponent2) {
                let row1 = [a, b].map { Analysis.value(data: store.data, scope: scope, deck: firstDeck, opponent: $0, source: source) }
                let row2 = [a, b].map { Analysis.value(data: store.data, scope: scope, deck: secondDeck, opponent: $0, source: source) }
                let min1 = Analysis.minimum(row1.map(\.percent)), min2 = Analysis.minimum(row2.map(\.percent))
                Section("2×2の相性") {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 16) {
                        GridRow { Text("自分 / 相手").font(.caption); Text(name(opponent1)).font(.caption.bold()); Text(name(opponent2)).font(.caption.bold()) }
                        GridRow { Text(store.data.deckName(firstDeck)).font(.caption.bold()); valueCell(row1[0]); valueCell(row1[1]) }
                        GridRow { Text(store.data.deckName(secondDeck)).font(.caption.bold()); valueCell(row2[0]); valueCell(row2[1]) }
                    }
                }
                Section("相手が最も厳しい候補を選んだ場合") {
                    LabeledContent(store.data.deckName(firstDeck), value: min1 == nil ? "算出不能" : percentage(min1))
                    LabeledContent(store.data.deckName(secondDeck), value: min2 == nil ? "算出不能" : percentage(min2))
                    if let safer = Analysis.safer(min1, min2) {
                        Text("✓ 安全候補：" + store.data.deckName(safer == 0 ? firstDeck : secondDeck)).font(.headline).foregroundStyle(.blue)
                    } else { Text(min1 == nil || min2 == nil ? "比較に必要な相性が不足しています。" : "最低値は同等です。") }
                    Text("表示は入力値の最小値です。実際の勝率を保証するものではありません。").font(.caption).foregroundStyle(.secondary)
                }
                if source == .actual && (row1 + row2).contains(where: { ($0.sampleCount ?? 0) < 10 }) {
                    Text("🌧️ 未対戦または少数サンプルを含みます。数字だけで選出を決めないでください。").font(.callout)
                }
                Section("計算の内訳") {
                    ForEach(Array((row1 + row2).enumerated()), id: \.offset) { index, value in
                        VStack(alignment: .leading) {
                            Text("\(store.data.deckName(index < 2 ? firstDeck : secondDeck)) → \(name(index % 2 == 0 ? opponent1 : opponent2))").font(.subheadline.bold())
                            ForEach(value.details, id: \.self) { Text($0).font(.caption) }
                        }
                    }
                }
            } else {
                Text(firstDeck != nil && firstDeck == secondDeck ? "自分のデッキは異なる2つを選んでください。" : "2デッキと相手2候補を選ぶと比較できます。").foregroundStyle(.secondary)
            }
        }.navigationTitle("持ち込み")
    }
    @ViewBuilder private var selectionFields: some View {
        deckPicker("デッキ1", selection: $firstDeck)
        deckPicker("デッキ2", selection: $secondDeck)
        opponentPicker("相手1", selection: $opponent1)
        opponentPicker("相手2", selection: $opponent2)
    }
    private func deckPicker(_ title: String, selection: Binding<UUID?>) -> some View {
        Picker(title, selection: selection) { Text("選択してください").tag(nil as UUID?); ForEach(store.data.decks.filter { !$0.archived }) { Text($0.name).tag(Optional($0.id)) } }
    }
    private func opponentPicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            Text("選択してください").tag("")
            Section("クラスのみ（設定した分布を使用）") { ForEach(CardClass.allCases) { Text(store.data.classTitle($0)).tag($0.rawValue) } }
            Section("アーキタイプ指定") { ForEach(store.data.archetypes.filter { !$0.archived && !store.data.isQuickDefaultArchetype($0.id) }) { Text($0.name).tag($0.id.uuidString) } }
        }
    }
    private func valueCell(_ value: MatchupValue) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value.percent == nil ? "未設定／未対戦" : percentage(value.percent)).font(.subheadline.bold()).monospacedDigit()
            if let n = value.sampleCount { Text("\(n)戦\n\(Stats.sample(n))").font(.caption2).foregroundStyle(.secondary) }
        }
    }
}
