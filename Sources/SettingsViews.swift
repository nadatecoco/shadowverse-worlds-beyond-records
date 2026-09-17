import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct SettingsView: View {
    @Environment(Store.self) private var store
    @Binding var scope: String
    @State private var exporting = false
    @State private var importing = false
    @State private var document = BackupDocument(data: Data())
    @State private var replacement: AppData?
    @State private var backupURL: URL?
    var body: some View {
        Form {
            Section("入力・表示") {
                NavigationLink("⚡ 高速入力を設定") { InputSetupView() }
                NavigationLink("クラスアイコンを変更") { ClassIconsEditor() }
            }
            Section("デッキと環境") {
                NavigationLink("自分の候補を追加・編集") { CatalogView(kind: .deck) }
                NavigationLink("相手アーキタイプ") { CatalogView(kind: .archetype) }
                NavigationLink("環境の作成・編集") { CatalogView(kind: .season) }
                Picker("記録先の現在環境", selection: Binding(get: { store.data.currentSeasonID }, set: { new in store.perform { $0.currentSeasonID = new } })) {
                    ForEach(store.data.seasons) { Text($0.name).tag(Optional($0.id)) }
                }
                Button("アーキタイプの例を取り込む") { store.addExamples() }
                Text("例は編集・削除できます。現在環境を切り替えても、過去の戦績や評価は移動しません。").font(.caption).foregroundStyle(.secondary)
            }
            Section("クラスしか分からない場合") {
                ScopePicker(scope: $scope)
                ForEach(CardClass.allCases) { cardClass in
                    NavigationLink(store.data.classTitle(cardClass) + "の分布") { DistributionEditor(scope: scope, cardClass: cardClass) }
                }
            }
            Section("バックアップ") {
                Button("JSONを書き出す") { do { document = BackupDocument(data: try store.export()); exporting = true } catch { store.error = error.localizedDescription } }
                Button("JSONから復元する") { importing = true }
                Text("復元は全データを置き換えます。実行前のデータはこのiPhone内に自動保存されます。").font(.caption).foregroundStyle(.secondary)
                if let backupURL { ShareLink("復元前バックアップを共有", item: backupURL) }
                NavigationLink("復元前バックアップ一覧") { BackupListView() }
            }
            Section("高速入力の設定") {
                NavigationLink("クイック入力の設定方法") { InputSetupView() }
                Text("非公式の個人用戦績ツールです。Shadowverse: Worlds Beyondの運営とは関係ありません。").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("デッキ／設定")
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "シャドバ戦績バックアップ") { result in if case .failure(let error) = result { store.error = error.localizedDescription } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get(); let accessed = url.startAccessingSecurityScopedResource(); defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 50_000_000 else { throw AppError.message("ファイルが大きすぎます（上限50MB）。") }
                    replacement = try Store.decodeBackup(Data(contentsOf: url, options: .mappedIfSafe))
                } catch { store.error = error.localizedDescription }
            }
            .alert("全データを復元しますか？", isPresented: Binding(get: { replacement != nil }, set: { if !$0 { replacement = nil } })) {
                Button("キャンセル", role: .cancel) { replacement = nil }
                Button("バックアップして復元", role: .destructive) {
                    guard let replacement else { return }
                    do { backupURL = try store.restore(replacement) } catch { store.error = error.localizedDescription }
                    self.replacement = nil
                }
            } message: { Text("現在 \(store.data.matches.count)戦 → 復元後 \(replacement?.matches.count ?? 0)戦\n環境 \(replacement?.seasons.count ?? 0)件、デッキ \(replacement?.decks.count ?? 0)件。現在のデータを置き換えます。") }
    }
}
enum CatalogKind: String { case deck = "自分のデッキ", archetype = "相手アーキタイプ", season = "環境" }
struct CatalogItem: Identifiable { var id: UUID; var name: String; var detail: String; var archived: Bool }
struct CatalogView: View {
    @Environment(Store.self) private var store
    let kind: CatalogKind
    @State private var editing: CatalogItem?
    @State private var adding = false
    @State private var deleting: CatalogItem?
    private var items: [CatalogItem] {
        switch kind {
        case .deck: store.data.decks.map { CatalogItem(id: $0.id, name: store.data.deckTitle($0.id), detail: $0.name == store.data.classForDeck($0.id)?.name ? "標準クラス" : "高速入力の候補", archived: $0.archived) }
        case .archetype: store.data.archetypes.filter { !store.data.isQuickDefaultArchetype($0.id) }.map { CatalogItem(id: $0.id, name: $0.name, detail: store.data.classTitle($0.cardClass), archived: $0.archived) }
        case .season: store.data.seasons.map { CatalogItem(id: $0.id, name: $0.name, detail: $0.id == store.data.currentSeasonID ? "現在の環境" : "", archived: false) }
        }
    }
    var body: some View {
        List {
            if items.isEmpty { Text("右上の＋から登録してください。").foregroundStyle(.secondary) }
            ForEach(items) { item in
                Button { editing = item } label: {
                    VStack(alignment: .leading) { Text(item.name + (item.archived ? "（アーカイブ）" : "")); Text(item.detail).font(.caption).foregroundStyle(.secondary) }.foregroundStyle(.primary)
                }.swipeActions { Button("削除", role: .destructive) { deleting = item } }
            }
            if kind != .season { Text("使用済み項目の削除はアーカイブになります。履歴は残り、編集画面から再表示できます。").font(.caption).foregroundStyle(.secondary) }
            else { Text("現在の環境、戦績・評価・分布がある環境は削除できません。").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle(kind.rawValue)
            .toolbar { Button("追加", systemImage: "plus") { adding = true } }
            .sheet(isPresented: $adding) { CatalogEditor(kind: kind) }
            .sheet(item: $editing) { CatalogEditor(kind: kind, itemID: $0.id) }
            .confirmationDialog("「\(deleting?.name ?? "")」を削除しますか？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("削除（使用済みはアーカイブ）", role: .destructive) { if let deleting { remove(deleting.id) }; deleting = nil }
            }
    }
    private func remove(_ id: UUID) {
        store.perform { data in
            switch kind {
            case .deck:
                if data.matches.contains(where: { $0.deckID == id }) || data.opinions.contains(where: { $0.deckID == id }) { data.decks[data.decks.firstIndex { $0.id == id }!].archived = true }
                else { data.decks.removeAll { $0.id == id } }
                if data.lastDeckID == id { data.lastDeckID = nil }
                if data.activeDeckID == id { data.activeDeckID = nil }
            case .archetype:
                if data.decks.contains(where: { $0.archetypeID == id }) || data.matches.contains(where: { $0.opponentID == id }) || data.opinions.contains(where: { $0.opponentID == id }) || data.distributions.contains(where: { $0.weights[id.uuidString] != nil }) {
                    data.archetypes[data.archetypes.firstIndex { $0.id == id }!].archived = true
                } else { data.archetypes.removeAll { $0.id == id } }
            case .season:
                guard data.currentSeasonID != id, !data.matches.contains(where: { $0.seasonID == id }), !data.opinions.contains(where: { $0.scope == id.uuidString }), !data.distributions.contains(where: { $0.scope == id.uuidString }) else { throw AppError.message("現在の環境やデータがある環境は削除できません。") }
                data.seasons.removeAll { $0.id == id }
            }
        }
    }
}
struct CatalogEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let kind: CatalogKind; var itemID: UUID?
    @State private var name = ""
    @State private var cardClass = CardClass.elf
    @State private var archetypeID: UUID?
    @State private var archived = false
    @State private var error: String?
    private var classificationLocked: Bool {
        guard let itemID else { return false }
        if kind == .deck { return store.data.matches.contains { $0.deckID == itemID } || store.data.opinions.contains { $0.deckID == itemID } }
        return store.data.decks.contains { $0.archetypeID == itemID } || store.data.matches.contains { $0.opponentID == itemID } || store.data.opinions.contains { $0.opponentID == itemID } || store.data.distributions.contains { $0.weights[itemID.uuidString] != nil }
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("名前", text: $name)
                if kind != .season {
                    Picker("クラス", selection: $cardClass) { ForEach(CardClass.allCases) { Text(store.data.classTitle($0)).tag($0) } }.disabled(classificationLocked)
                    if kind == .deck {
                        Text("例：エルフを選び、名前に「ダストデイズエルフ」や「リノセウスエルフ」と入力します。高速入力の自分側候補へ追加されます。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if classificationLocked { Text("使用済みの分類は変更できません。別の項目として新規登録してください。").font(.caption).foregroundStyle(.secondary) }
                    if itemID != nil { Toggle("アーカイブ（入力候補に表示しない）", isOn: $archived) }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle(kind.rawValue + (itemID == nil ? "を追加" : "を編集"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
                .onAppear {
                    switch kind {
                    case .deck:
                        if let value = store.data.decks.first(where: { $0.id == itemID }) { name = value.name; archetypeID = value.archetypeID; cardClass = store.data.classForDeck(value.id) ?? .elf; archived = value.archived }
                    case .archetype:
                        if let value = store.data.archetypes.first(where: { $0.id == itemID }) { name = value.name; cardClass = value.cardClass; archived = value.archived }
                    case .season: name = store.data.seasons.first { $0.id == itemID }?.name ?? ""
                    }
                }
                .onChange(of: cardClass) { _, new in if !store.data.archetypes.contains(where: { $0.id == archetypeID && $0.cardClass == new }) { archetypeID = nil } }
        }
    }
    private func save() {
        do { try store.commit { data in
            let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            switch kind {
            case .deck:
                let archetypeID: UUID
                if classificationLocked, let existing = data.decks.first(where: { $0.id == itemID }) {
                    archetypeID = existing.archetypeID
                } else if let existing = data.archetypes.first(where: { $0.name == clean && $0.cardClass == cardClass }) {
                    archetypeID = existing.id
                } else {
                    let created = Archetype(name: clean, cardClass: cardClass)
                    data.archetypes.append(created); archetypeID = created.id
                }
                let value = Deck(id: itemID ?? UUID(), name: clean, archetypeID: archetypeID, archived: archived)
                if let index = data.decks.firstIndex(where: { $0.id == itemID }) { data.decks[index] = value } else { data.decks.append(value) }
                if data.lastDeckID == nil && !archived { data.lastDeckID = value.id }
                if data.decks.count == 1 && data.activeDeckID == nil && !archived { data.activeDeckID = value.id }
            case .archetype:
                let value = Archetype(id: itemID ?? UUID(), name: clean, cardClass: cardClass, archived: archived)
                if let index = data.archetypes.firstIndex(where: { $0.id == itemID }) { data.archetypes[index] = value } else { data.archetypes.append(value) }
            case .season:
                if let index = data.seasons.firstIndex(where: { $0.id == itemID }) { data.seasons[index].name = clean }
                else { data.seasons.append(Season(name: clean)) }
            }
        }; dismiss() } catch { self.error = error.localizedDescription }
    }
}
struct DistributionEditor: View {
    @Environment(Store.self) private var store
    let scope: String; let cardClass: CardClass
    @State private var weights: [String: Double] = [:]
    @State private var message: String?
    var body: some View {
        Form {
            Section("合計 \(Int(weights.values.reduce(0, +)))% / 100%") {
                ForEach(store.data.archetypes.filter { $0.cardClass == cardClass && !store.data.isQuickDefaultArchetype($0.id) }) { archetype in
                    Stepper("\(archetype.name)：\(Int(weights[archetype.id.uuidString] ?? 0))%", value: Binding(get: { weights[archetype.id.uuidString] ?? 0 }, set: { weights[archetype.id.uuidString] = $0 }), in: 0...100, step: 1)
                }
                Text("1%刻みで設定します。合計100%で保存できます。割合が正の候補に未設定・未対戦がある場合、期待相性は算出しません。").font(.caption).foregroundStyle(.secondary)
            }
            Button("分布を保存") {
                do { try store.commit { data in
                    data.distributions.removeAll { $0.scope == scope && $0.cardClass == cardClass }
                    data.distributions.append(Distribution(scope: scope, cardClass: cardClass, weights: weights.filter { $0.value > 0 }))
                }; message = "保存しました。" } catch { message = error.localizedDescription }
            }.disabled(abs(weights.values.reduce(0, +) - 100) > 0.001)
            Button("分布を未設定に戻す", role: .destructive) {
                do { try store.commit { $0.distributions.removeAll { $0.scope == scope && $0.cardClass == cardClass } }; weights = [:]; message = "未設定に戻しました。" } catch { message = error.localizedDescription }
            }
            if let message { Text(message) }
        }.navigationTitle(store.data.classTitle(cardClass))
            .onAppear { weights = store.data.distributions.first { $0.scope == scope && $0.cardClass == cardClass }?.weights ?? [:] }
    }
}
struct BackupListView: View {
    @State private var urls: [URL] = []
    var body: some View {
        List {
            if urls.isEmpty { Text("復元前バックアップはありません。") }
            ForEach(urls, id: \.self) { ShareLink($0.lastPathComponent, item: $0) }
        }.navigationTitle("復元前バックアップ")
            .onAppear { urls = ((try? FileManager.default.contentsOfDirectory(at: URL.documentsDirectory.appending(path: "復元前バックアップ"), includingPropertiesForKeys: nil)) ?? []).sorted { $0.lastPathComponent > $1.lastPathComponent } }
    }
}
