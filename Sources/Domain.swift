import Foundation

enum CardClass: String, Codable, CaseIterable, Identifiable, Sendable {
    case elf, royal, witch, dragon, nightmare, bishop, nemesis
    var id: String { rawValue }
    var name: String { String(title.dropFirst(2)) }
    var defaultIcon: String { String(title.prefix(1)) }
    var title: String {
        switch self {
        case .elf: "🧚 エルフ"
        case .royal: "⚔️ ロイヤル"
        case .witch: "🧙 ウィッチ"
        case .dragon: "🐉 ドラゴン"
        case .nightmare: "😈 ナイトメア"
        case .bishop: "⛪ ビショップ"
        case .nemesis: "🤖 ネメシス"
        }
    }
}
struct Archetype: Codable, Identifiable, Equatable, Sendable {
    var id = UUID(); var name: String; var cardClass: CardClass; var archived = false
}
struct Deck: Codable, Identifiable, Equatable, Sendable {
    var id = UUID(); var name: String; var archetypeID: UUID; var archived = false
}
struct Season: Codable, Identifiable, Equatable, Sendable {
    var id = UUID(); var name: String; var createdAt = Date()
}
struct Match: Codable, Identifiable, Equatable, Sendable {
    var id = UUID(); var date = Date(); var seasonID: UUID; var deckID: UUID
    var opponentClass: CardClass?; var opponentID: UUID?; var won: Bool; var first: Bool; var note = ""
}
struct Opinion: Codable, Identifiable, Equatable, Sendable {
    var id = UUID(); var scope: String; var deckID: UUID; var opponentID: UUID; var percent: Double
}
struct ClassOpinion: Codable, Identifiable, Equatable, Sendable {
    var id = UUID(); var scope: String; var deckID: UUID; var opponentClass: CardClass; var percent: Double
}
struct Distribution: Codable, Identifiable, Equatable, Sendable {
    var id = UUID(); var scope: String; var cardClass: CardClass; var weights: [String: Double]
}
struct AppData: Codable, Equatable, Sendable {
    var version = 3
    var archetypes: [Archetype] = []; var decks: [Deck] = []; var seasons: [Season] = []
    var matches: [Match] = []; var opinions: [Opinion] = []; var classOpinions: [ClassOpinion] = []; var distributions: [Distribution] = []
    var classIcons: [String: String]? = nil
    func icon(for cardClass: CardClass) -> String { classIcons?[cardClass.rawValue] ?? cardClass.defaultIcon }
    func classTitle(_ cardClass: CardClass) -> String { icon(for: cardClass) + " " + cardClass.name }
    static func validIcon(_ value: String) -> Bool {
        value.count == 1 && value.unicodeScalars.contains { $0.properties.isEmoji && $0.value > 0x7f }
    }
    var currentSeasonID: UUID?; var lastDeckID: UUID?
    var activeDeckID: UUID? = nil
    private enum CodingKeys: String, CodingKey { case version, archetypes, decks, seasons, matches, opinions, classOpinions, distributions, classIcons, currentSeasonID, lastDeckID, activeDeckID }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 2
        archetypes = try c.decodeIfPresent([Archetype].self, forKey: .archetypes) ?? []
        decks = try c.decodeIfPresent([Deck].self, forKey: .decks) ?? []
        seasons = try c.decodeIfPresent([Season].self, forKey: .seasons) ?? []
        matches = try c.decodeIfPresent([Match].self, forKey: .matches) ?? []
        opinions = try c.decodeIfPresent([Opinion].self, forKey: .opinions) ?? []
        classOpinions = try c.decodeIfPresent([ClassOpinion].self, forKey: .classOpinions) ?? []
        distributions = try c.decodeIfPresent([Distribution].self, forKey: .distributions) ?? []
        classIcons = try c.decodeIfPresent([String: String].self, forKey: .classIcons)
        currentSeasonID = try c.decodeIfPresent(UUID.self, forKey: .currentSeasonID)
        lastDeckID = try c.decodeIfPresent(UUID.self, forKey: .lastDeckID)
        activeDeckID = try c.decodeIfPresent(UUID.self, forKey: .activeDeckID)
    }
    static func fresh() -> Self {
        var value = Self(); let season = Season(name: "現在の環境")
        value.seasons = [season]; value.currentSeasonID = season.id; return value
    }
    func deckName(_ id: UUID) -> String { decks.first { $0.id == id }?.name ?? "削除済みデッキ" }
    func archetypeName(_ id: UUID?) -> String { archetypes.first { $0.id == id }?.name ?? "不明" }
    func seasonName(_ id: UUID?) -> String { seasons.first { $0.id == id }?.name ?? "環境なし" }
    func classForDeck(_ id: UUID) -> CardClass? {
        guard let deck = decks.first(where: { $0.id == id }) else { return nil }
        return archetypes.first { $0.id == deck.archetypeID }?.cardClass
    }
    func filtered(_ scope: String, deckID: UUID? = nil) -> [Match] {
        matches.filter { (scope == "all" || $0.seasonID.uuidString == scope) && (deckID == nil || $0.deckID == deckID) }
    }
    mutating func migrate() throws {
        guard (1...3).contains(version) else { throw AppError.message("未対応のデータ形式です。") }
        if version == 1 {
            activeDeckID = decks.first { $0.id == lastDeckID && !$0.archived }?.id
            version = 2
        }
        if version == 2 { version = 3 }
    }
    var activeDeck: Deck? { decks.first { $0.id == activeDeckID && !$0.archived } }
    func deckTitle(_ id: UUID) -> String {
        guard let deck = decks.first(where: { $0.id == id }) else { return "削除済みデッキ" }
        guard let cardClass = classForDeck(id) else { return deck.name }
        return deck.name == cardClass.name ? classTitle(cardClass) : "\(classTitle(cardClass))（\(deck.name)）"
    }

    /// 高速入力を初回から使えるようにする7クラスの標準候補。
    /// 既存モデルをそのまま使うため、固定IDで重複作成を防ぐ。
    static let quickDefaults: [(CardClass, UUID, UUID)] = [
        (.elf, UUID(uuidString: "10000000-0000-4000-8000-000000000001")!, UUID(uuidString: "20000000-0000-4000-8000-000000000001")!),
        (.royal, UUID(uuidString: "10000000-0000-4000-8000-000000000002")!, UUID(uuidString: "20000000-0000-4000-8000-000000000002")!),
        (.witch, UUID(uuidString: "10000000-0000-4000-8000-000000000003")!, UUID(uuidString: "20000000-0000-4000-8000-000000000003")!),
        (.dragon, UUID(uuidString: "10000000-0000-4000-8000-000000000004")!, UUID(uuidString: "20000000-0000-4000-8000-000000000004")!),
        (.nightmare, UUID(uuidString: "10000000-0000-4000-8000-000000000005")!, UUID(uuidString: "20000000-0000-4000-8000-000000000005")!),
        (.bishop, UUID(uuidString: "10000000-0000-4000-8000-000000000006")!, UUID(uuidString: "20000000-0000-4000-8000-000000000006")!),
        (.nemesis, UUID(uuidString: "10000000-0000-4000-8000-000000000007")!, UUID(uuidString: "20000000-0000-4000-8000-000000000007")!)
    ]
    func isQuickDefaultArchetype(_ id: UUID) -> Bool { Self.quickDefaults.contains { $0.1 == id } }
    func isQuickDefaultDeck(_ id: UUID) -> Bool { Self.quickDefaults.contains { $0.2 == id } }

    @discardableResult mutating func ensureQuickEntryDefaults() -> Bool {
        var changed = false
        if seasons.isEmpty {
            let season = Season(name: "現在の環境")
            seasons = [season]; currentSeasonID = season.id; changed = true
        } else if currentSeasonID == nil || !seasons.contains(where: { $0.id == currentSeasonID }) {
            currentSeasonID = seasons[0].id; changed = true
        }
        for (cardClass, archetypeID, deckID) in Self.quickDefaults {
            if let index = archetypes.firstIndex(where: { $0.id == archetypeID }) {
                if archetypes[index].archived { archetypes[index].archived = false; changed = true }
            } else {
                archetypes.append(Archetype(id: archetypeID, name: cardClass.name, cardClass: cardClass))
                changed = true
            }
            if let index = decks.firstIndex(where: { $0.id == deckID }) {
                if decks[index].archived { decks[index].archived = false; changed = true }
            } else {
                decks.append(Deck(id: deckID, name: cardClass.name, archetypeID: archetypeID))
                changed = true
            }
        }
        if lastDeckID == nil || !decks.contains(where: { $0.id == lastDeckID && !$0.archived }) {
            lastDeckID = Self.quickDefaults[0].2; changed = true
        }
        return changed
    }
    func validate() throws {
        guard (classIcons ?? [:]).allSatisfy({ CardClass(rawValue: $0.key) != nil && Self.validIcon($0.value) }) else { throw AppError.message("クラスアイコンには絵文字を1つ指定してください。") }
        guard version == 3 else { throw AppError.message("このバックアップの形式には対応していません。") }
        func unique<T: Identifiable>(_ values: [T]) -> Bool where T.ID: Hashable {
            Set(values.map(\.id)).count == values.count
        }
        guard unique(archetypes), unique(decks), unique(seasons), unique(matches), unique(opinions), unique(classOpinions), unique(distributions) else {
            throw AppError.message("識別番号が重複しています。")
        }
        let archetypeIDs = Set(archetypes.map(\.id)), deckIDs = Set(decks.map(\.id)), seasonIDs = Set(seasons.map(\.id))
        func validScope(_ scope: String) -> Bool { scope == "all" || seasons.contains { $0.id.uuidString == scope } }
        guard let currentSeasonID, seasonIDs.contains(currentSeasonID),
              lastDeckID == nil || deckIDs.contains(lastDeckID!),
              activeDeckID == nil || deckIDs.contains(activeDeckID!),
              !seasons.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              !archetypes.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              decks.allSatisfy({ archetypeIDs.contains($0.archetypeID) && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw AppError.message("環境・デッキ・アーキタイプの参照先や名前が不正です。")
        }
        for match in matches {
            guard seasonIDs.contains(match.seasonID), deckIDs.contains(match.deckID), match.date.timeIntervalSince1970.isFinite else {
                throw AppError.message("戦績の参照先が見つかりません。")
            }
            if let opponent = match.opponentID {
                guard archetypes.contains(where: { $0.id == opponent && $0.cardClass == match.opponentClass }) else {
                    throw AppError.message("相手クラスとアーキタイプが一致しません。")
                }
            }
        }
        var opinionKeys = Set<String>()
        for value in opinions {
            let key = "\(value.scope)/\(value.deckID)/\(value.opponentID)"
            guard validScope(value.scope), deckIDs.contains(value.deckID), archetypeIDs.contains(value.opponentID),
                  value.percent.isFinite, (0...100).contains(value.percent), opinionKeys.insert(key).inserted else {
                throw AppError.message("主観相性の値または組み合わせが不正です。")
            }
        }
        var classOpinionKeys = Set<String>()
        for value in classOpinions {
            let key = "\(value.scope)/\(value.deckID)/\(value.opponentClass.rawValue)"
            guard validScope(value.scope), deckIDs.contains(value.deckID), value.percent.isFinite, (0...100).contains(value.percent), classOpinionKeys.insert(key).inserted else {
                throw AppError.message("クラス主観相性の値または組み合わせが不正です。")
            }
        }
        var distributionKeys = Set<String>()
        for value in distributions {
            guard validScope(value.scope), distributionKeys.insert(value.scope + value.cardClass.rawValue).inserted,
                  !value.weights.isEmpty, abs(value.weights.values.reduce(0, +) - 100) < 0.001 else {
                throw AppError.message("分布の合計は100%にしてください。")
            }
            for (id, weight) in value.weights {
                guard weight.isFinite, (0...100).contains(weight), archetypes.contains(where: { $0.id.uuidString == id && $0.cardClass == value.cardClass }) else {
                    throw AppError.message("分布のクラス・アーキタイプ・割合が不正です。")
                }
            }
        }
    }
}
enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { message } else { nil } }
}
struct Stats: Equatable {
    var wins: Int; var losses: Int; var firstWins: Int; var firstLosses: Int; var secondWins: Int; var secondLosses: Int
    init(_ matches: [Match]) {
        wins = matches.filter(\.won).count; losses = matches.count - wins
        firstWins = matches.filter { $0.first && $0.won }.count
        firstLosses = matches.filter { $0.first && !$0.won }.count
        secondWins = matches.filter { !$0.first && $0.won }.count
        secondLosses = matches.filter { !$0.first && !$0.won }.count
    }
    var count: Int { wins + losses }
    var rate: Double? { count == 0 ? nil : Double(wins) / Double(count) * 100 }
    var sample: String { Self.sample(count) }
    static func sample(_ count: Int) -> String {
        switch count { case 0: "未対戦"; case 1...9: "🌧️ サンプル少"; case 10...29: "☁️ 中程度"; default: "☀️ 十分" }
    }
}
func percentage(_ value: Double?) -> String { value.map { String(format: "%.1f%%", $0) } ?? "—" }
enum ValueSource: String, CaseIterable, Identifiable {
    case opinion = "🧠 主観", actual = "📊 実戦"
    var id: String { rawValue }
}
enum Opponent: Hashable {
    case archetype(UUID), cardClass(CardClass)
}
struct MatchupValue {
    var percent: Double?; var sampleCount: Int?; var details: [String]
}
enum Analysis {
    static func classValue(data: AppData, scope: String, deck: UUID, opponentClass: CardClass, source: ValueSource) -> MatchupValue {
        if source == .opinion {
            return MatchupValue(percent: data.classOpinions.first { $0.scope == scope && $0.deckID == deck && $0.opponentClass == opponentClass }?.percent, sampleCount: nil, details: [])
        }
        let stats = Stats(data.filtered(scope, deckID: deck).filter { $0.opponentClass == opponentClass })
        return MatchupValue(percent: stats.rate, sampleCount: stats.count,
                            details: ["\(stats.wins)勝\(stats.losses)敗 / \(stats.count)戦", "先攻 \(stats.firstWins)-\(stats.firstLosses) ・ 後攻 \(stats.secondWins)-\(stats.secondLosses)"])
    }
    static func value(data: AppData, scope: String, deck: UUID, opponent: Opponent, source: ValueSource) -> MatchupValue {
        switch opponent {
        case .archetype(let id):
            if source == .opinion {
                return MatchupValue(percent: data.opinions.first { $0.scope == scope && $0.deckID == deck && $0.opponentID == id }?.percent,
                                    sampleCount: nil, details: [])
            }
            let stats = Stats(data.filtered(scope, deckID: deck).filter { $0.opponentID == id })
            return MatchupValue(percent: stats.rate, sampleCount: stats.count,
                                details: ["\(stats.wins)勝\(stats.losses)敗 / \(stats.count)戦", "先攻 \(stats.firstWins)-\(stats.firstLosses) ・ 後攻 \(stats.secondWins)-\(stats.secondLosses)"])
        case .cardClass(let cardClass):
            guard let distribution = data.distributions.first(where: { $0.scope == scope && $0.cardClass == cardClass }) else {
                return MatchupValue(percent: nil, sampleCount: nil, details: ["アーキタイプ分布が未設定"])
            }
            var sum = 0.0; var samples: [Int] = []; var details: [String] = []; var complete = true
            for (key, weight) in distribution.weights.sorted(by: { $0.key < $1.key }) where weight > 0 {
                guard let id = UUID(uuidString: key) else { complete = false; continue }
                let part = value(data: data, scope: scope, deck: deck, opponent: .archetype(id), source: source)
                if let p = part.percent { sum += p * weight / 100 } else { complete = false }
                if let n = part.sampleCount { samples.append(n) }
                details.append("\(data.archetypeName(id)) \(Int(weight))% → \(percentage(part.percent))" + (part.sampleCount.map { " / \($0)戦" } ?? ""))
            }
            return MatchupValue(percent: complete ? sum : nil, sampleCount: samples.min(), details: details)
        }
    }
    static func minimum(_ row: [Double?]) -> Double? {
        guard row.count == 2, row.allSatisfy({ $0 != nil }) else { return nil }; return row.compactMap { $0 }.min()
    }
    static func safer(_ first: Double?, _ second: Double?) -> Int? {
        guard let first, let second, abs(first - second) > 0.000001 else { return nil }; return first > second ? 0 : 1
    }
}
