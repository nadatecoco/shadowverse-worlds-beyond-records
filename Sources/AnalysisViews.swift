import SwiftUI

struct CellSelection: Identifiable { var id: String { "\(deck)/\(opponent)" }; var deck: UUID; var opponent: UUID }
struct ClassCellSelection: Identifiable { var id: String { "\(deck)/\(opponentClass.rawValue)" }; var deck: UUID; var opponentClass: CardClass }

struct MatrixView: View {
    @Environment(Store.self) private var store
    @Binding var scope: String
    @State private var mode = 2
    @State private var selected: ClassCellSelection?
    private var decks: [Deck] { store.data.decks.filter { !$0.archived && !store.data.isQuickDefaultDeck($0.id) } }
    var body: some View {
        VStack(spacing: 12) {
            VStack { ScopePicker(scope: $scope); Picker("表示", selection: $mode) { Text("🧠 主観").tag(0); Text("📊 実戦").tag(1); Text("両方").tag(2) }.pickerStyle(.segmented) }.padding(.horizontal)
            if decks.isEmpty {
                ContentUnavailableView("自分のデッキを登録してください", systemImage: "tablecells", description: Text("「デッキ／設定」で登録したデッキがここに表示されます。"))
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Grid(alignment: .topLeading, horizontalSpacing: 1, verticalSpacing: 1) {
                        GridRow {
                            Text("自分 ↓ / 相手 →").font(.caption).frame(width: 132, height: 54)
                            ForEach(CardClass.allCases) { cls in
                                Text(store.data.classTitle(cls)).font(.caption.bold()).multilineTextAlignment(.center).frame(width: 96, height: 54).accessibilityLabel(store.data.classTitle(cls))
                            }
                        }
                        ForEach(decks) { deck in
                            GridRow {
                                Text(store.data.deckTitle(deck.id)).font(.caption.bold()).frame(width: 132, alignment: .leading).padding(8)
                                ForEach(CardClass.allCases) { cls in
                                    let opinion = Analysis.classValue(data: store.data, scope: scope, deck: deck.id, opponentClass: cls, source: .opinion)
                                    let actual = Analysis.classValue(data: store.data, scope: scope, deck: deck.id, opponentClass: cls, source: .actual)
                                    Button { selected = ClassCellSelection(deck: deck.id, opponentClass: cls) } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            if mode != 1 { Text("🧠" + (opinion.percent.map { String(Int($0.rounded())) } ?? "—")).monospacedDigit() }
                                            if mode != 0 { Text("📊" + (actual.percent.map { String(Int($0.rounded())) } ?? "—")).monospacedDigit(); Text(actual.sampleCount == 0 ? "未対戦" : "\(actual.sampleCount!)戦").font(.caption2).foregroundStyle(.secondary) }
                                        }.frame(width: 88, minHeight: 64, alignment: .leading).padding(6).background(.quaternary.opacity(0.5))
                                    }.buttonStyle(.plain).accessibilityLabel("\(store.data.deckTitle(deck.id)) 対 \(store.data.classTitle(cls))")
                                }
                            }
                        }
                    }.padding(.horizontal)
                }.defaultScrollAnchor(.topLeading)
            }
            Text("セルをタップすると、クラス全体の主観値・実戦値とアーキタイプ別の内訳を確認できます。").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
        }.navigationTitle("相性表").sheet(item: $selected) { ClassOpinionEditor(scope: scope, selection: $0) }
    }
}

struct ClassOpinionEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let scope: String; let selection: ClassCellSelection
    @State private var percent = 50.0
    @State private var error: String?
    @State private var archetypeSelection: CellSelection?
    private var stats: Stats { Stats(store.data.filtered(scope, deckID: selection.deck).filter { $0.opponentClass == selection.opponentClass }) }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(store.data.deckTitle(selection.deck)); Text("対 " + store.data.classTitle(selection.opponentClass)) }
                Section("🧠 自分の評価") {
                    HStack { ForEach([40.0,45.0,50.0,55.0,60.0], id: \.self) { value in Button("\(Int(value))") { percent = value }.buttonStyle(.bordered) } }
                    Stepper("\(Int(percent.rounded()))%", value: $percent, in: 0...100, step: 1)
                    Button("主観値をリセット", role: .destructive) { do { try store.commit { $0.classOpinions.removeAll { $0.scope == scope && $0.deckID == selection.deck && $0.opponentClass == selection.opponentClass } }; dismiss() } catch { error = error.localizedDescription } }
                }
                Section("📊 実戦値") { StatsView(stats: stats); Text("先攻：\(stats.firstWins)勝\(stats.firstLosses)敗"); Text("後攻：\(stats.secondWins)勝\(stats.secondLosses)敗"); Text(stats.count == 0 ? "未対戦" : stats.sample) }
                let archetypes = store.data.archetypes.filter { !$0.archived && !store.data.isQuickDefaultArchetype($0.id) && $0.cardClass == selection.opponentClass }
                if !archetypes.isEmpty { Section("アーキタイプ別") { ForEach(archetypes) { archetype in
                    let actual = Analysis.value(data: store.data, scope: scope, deck: selection.deck, opponent: .archetype(archetype.id), source: .actual)
                    let opinion = Analysis.value(data: store.data, scope: scope, deck: selection.deck, opponent: .archetype(archetype.id), source: .opinion)
                    Button { archetypeSelection = CellSelection(deck: selection.deck, opponent: archetype.id) } label: { HStack { Text(archetype.name); Spacer(); Text("🧠\(opinion.percent.map { String(Int($0.rounded())) } ?? "—")  📊\(actual.percent.map { String(Int($0.rounded())) } ?? "—")") } }
                } } }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("クラス相性の詳細").toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { do { try store.commit { data in data.classOpinions.removeAll { $0.scope == scope && $0.deckID == selection.deck && $0.opponentClass == selection.opponentClass }; data.classOpinions.append(ClassOpinion(scope: scope, deckID: selection.deck, opponentClass: selection.opponentClass, percent: percent)) }; dismiss() } catch { error = error.localizedDescription } } } }.onAppear { percent = store.data.classOpinions.first { $0.scope == scope && $0.deckID == selection.deck && $0.opponentClass == selection.opponentClass }?.percent ?? 50 }
        }.sheet(item: $archetypeSelection) { OpinionEditor(scope: scope, selection: $0) }
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
