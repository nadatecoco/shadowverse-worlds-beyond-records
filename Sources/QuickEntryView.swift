import SwiftUI

struct QuickEntryView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var id = UUID()
    @State private var deckID: UUID?
    @State private var seasonID: UUID?
    @State private var cardClass: CardClass?
    @State private var opponentID: UUID?
    @State private var result: Int?
    @State private var note = ""
    @State private var error: String?
    @State private var saved = false
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    private var choices: [Archetype] {
        store.data.archetypes.filter { $0.cardClass == cardClass && !$0.archived && !store.data.isQuickDefaultArchetype($0.id) }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    DisclosureGroup {
                        Picker("自分のデッキ", selection: $deckID) {
                            ForEach(store.data.decks.filter { !$0.archived }) { Text($0.name).tag(Optional($0.id)) }
                        }
                        Picker("環境", selection: $seasonID) {
                            ForEach(store.data.seasons) { Text($0.name).tag(Optional($0.id)) }
                        }
                    } label: {
                        Text(deckID.map { store.data.deckName($0) } ?? "自分のデッキを登録してください")
                    }
                    if deckID == nil || seasonID == nil {
                        Text("いったん閉じて「デッキ／設定」で自分のデッキと現在環境を設定してください。")
                    }
                    Text("相手クラス").font(.headline)
                    LazyVGrid(columns: columns) {
                        ForEach(CardClass.allCases) { value in
                            Button(store.data.classTitle(value)) {
                                cardClass = value; opponentID = nil
                            }.tint(cardClass == value ? .blue : .gray)
                                .accessibilityAddTraits(cardClass == value ? .isSelected : [])
                        }
                    }
                    if cardClass != nil {
                        if !choices.isEmpty {
                            Text("アーキタイプ（任意）").font(.headline)
                            LazyVGrid(columns: columns) {
                                Button("不明") { opponentID = nil }.tint(opponentID == nil ? .blue : .gray)
                                ForEach(choices) { value in
                                    Button(value.name) { opponentID = value.id }.tint(opponentID == value.id ? .blue : .gray)
                                }
                            }
                        }
                        Text("勝敗・先後").font(.headline)
                        LazyVGrid(columns: columns) {
                            ForEach(0..<4) { value in
                                Button(resultTitle(value)) { result = value }
                                    .tint(result == value ? .blue : .gray)
                                    .accessibilityAddTraits(result == value ? .isSelected : [])
                            }
                        }
                    }
                    DisclosureGroup("詳細（任意）") {
                        Text("日時は保存時に自動で記録します。").font(.caption)
                        TextField("メモ", text: $note, axis: .vertical)
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                }.padding().buttonStyle(.bordered)
            }
            .navigationTitle("戦績を記録")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(deckID == nil || seasonID == nil || cardClass == nil || result == nil || saved)
                }
            }
            .onAppear {
                deckID = store.data.decks.first { $0.id == store.data.lastDeckID && !$0.archived }?.id
                    ?? store.data.decks.first { !$0.archived }?.id
                seasonID = store.data.currentSeasonID
            }
        }
    }
    private func save() {
        guard !saved, let deckID, let seasonID, let cardClass, let result else { return }
        do {
            guard store.data.decks.contains(where: { $0.id == deckID && !$0.archived }),
                  store.data.seasons.contains(where: { $0.id == seasonID }) else {
                throw AppError.message("デッキまたは環境が変更されました。選び直してください。")
            }
            try store.recordOnce(Match(id: id, date: Date(), seasonID: seasonID, deckID: deckID,
                                      opponentClass: cardClass, opponentID: opponentID,
                                      won: result % 2 == 0, first: result < 2, note: note))
            saved = true
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
