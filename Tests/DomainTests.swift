import XCTest
import SwiftData
@testable import ShadowRecord

final class DomainTests: XCTestCase {
    @MainActor func testClassIconsCompatibilityAndPersistence() throws {
        let original = fixture()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "classIcons")
        let old = try Store.decodeBackup(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.classTitle(.elf), "🧚 エルフ")
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "data.store")
        let store = Store(storageURL: url)
        try store.commit { $0.classIcons = ["elf": "🌳", "witch": "🪄"] }
        XCTAssertEqual(Store(storageURL: url).data.classTitle(.elf), "🌳 エルフ")
        let restored = try Store.decodeBackup(store.export())
        XCTAssertEqual(restored.classTitle(.witch), "🪄 ウィッチ")
        XCTAssertThrowsError(try store.commit { $0.classIcons = ["elf": "abc"] })
        XCTAssertEqual(store.data.icon(for: .elf), "🌳")
        for invalid in ["", "1", "🌳🌳"] { XCTAssertFalse(AppData.validIcon(invalid)) }
        XCTAssertTrue(AppData.validIcon("🧑🏽‍💻"))
        try store.commit { $0.classIcons = nil }
        XCTAssertEqual(store.data.classTitle(.elf), "🧚 エルフ")
    }
    @MainActor func testControlOpensEntryWithoutSaving() async throws {
        let count = Store.shared.data.matches.count
        Store.shared.showQuickEntry = false
        _ = try await OpenRecordControlIntent().perform()
        XCTAssertTrue(Store.shared.showQuickEntry)
        XCTAssertEqual(Store.shared.data.matches.count, count)
        Store.shared.showQuickEntry = false
    }
    @MainActor func testEmptyClassSkipsArchetypeAndMissingDeck() async throws {
        let store = Store.shared
        let original = store.data
        defer { try? store.commit { $0 = original } }
        try store.commit { $0 = AppData.fresh() }
        XCTAssertThrowsError(try QuickSessions.begin(store: store))
        try store.commit { $0 = fixture() }
        let key = try QuickSessions.begin(store: store)
        defer { QuickSessions.drafts.removeValue(forKey: key) }
        _ = try await UpdateQuickInput(session: key, operation: "class", value: "elf").perform()
        XCTAssertEqual(QuickSessions.drafts[key]?.stage, 2)
        XCTAssertEqual(QuickSessions.drafts[key]?.opponentChosen, true)
        XCTAssertNil(QuickSessions.drafts[key]?.opponentID)
        _ = try await UpdateQuickInput(session: key, operation: "result", value: "0").perform()
        let match = try QuickSessions.match(key, store: store)
        try store.commit { $0.decks[0].archived = true }
        XCTAssertThrowsError(try QuickSessions.match(key, store: store))
        XCTAssertNotNil(QuickSessions.drafts[key])
        XCTAssertTrue(store.data.matches.isEmpty)
        try store.commit { $0.decks[0].archived = false }
        try store.recordOnce(match)
        try store.recordOnce(match)
        XCTAssertEqual(store.data.matches.count, 1)
    }
    @MainActor func testOneTapDraftSaveDedupAndLiveStats() throws {
        let store = Store(inMemory: true)
        try store.commit { $0 = fixture() }
        let key = try OneTapRecords.begin(store)
        defer { OneTapRecords.sessions.removeValue(forKey: key) }
        try OneTapRecords.selectOpponentClass(key, cardClass: .witch)
        try OneTapRecords.selectOutcome(key, first: true, won: true)
        XCTAssertTrue(store.data.matches.isEmpty)
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        try OneTapRecords.save(key, store: store, now: timestamp)
        try OneTapRecords.save(key, store: store)
        XCTAssertEqual(store.data.matches.count, 1)
        XCTAssertEqual(store.data.matches[0].opponentClass, .witch)
        XCTAssertEqual(store.data.matches[0].date, timestamp)
        XCTAssertTrue(store.data.matches[0].won)
        XCTAssertTrue(store.data.matches[0].first)
        let live = try XCTUnwrap(LiveRecords.content(store.data))
        XCTAssertEqual(live.wins, 1); XCTAssertEqual(live.losses, 0); XCTAssertEqual(live.streak, 1)
        XCTAssertEqual(live.rate, "100.0%")
        XCTAssertNil(Analysis.value(data: store.data, scope: "all", deck: store.data.decks[0].id, opponent: .cardClass(.dragon), source: .actual).percent)
    }
    @MainActor func testOneTapDeckCycleResultsAndInvalidation() throws {
        let store = Store(inMemory: true)
        try store.commit { $0 = fixture() }
        try store.commit { data in
            data.decks.append(Deck(name: "別デッキ", archetypeID: data.archetypes[1].id))
        }
        let key = try OneTapRecords.begin(store)
        defer { OneTapRecords.sessions.removeValue(forKey: key) }
        let firstDeck = try XCTUnwrap(OneTapRecords.sessions[key]?.deckID)
        let deckCount = store.data.decks.filter { !$0.archived }.count
        try OneTapRecords.cycleDeck(key, direction: 1, store: store)
        let secondDeck = try XCTUnwrap(OneTapRecords.sessions[key]?.deckID)
        XCTAssertNotEqual(secondDeck, firstDeck)
        for _ in 1..<deckCount { try OneTapRecords.cycleDeck(key, direction: 1, store: store) }
        XCTAssertEqual(OneTapRecords.sessions[key]?.deckID, firstDeck)
        try OneTapRecords.cycleDeck(key, direction: -1, store: store)
        XCTAssertThrowsError(try OneTapRecords.save(key, store: store))
        try OneTapRecords.selectOpponentClass(key, cardClass: .dragon)
        try OneTapRecords.selectOutcome(key, first: false, won: false)
        let selectedDeck = try XCTUnwrap(OneTapRecords.sessions[key]?.deckID)
        try store.commit { $0.decks.removeAll { $0.id == selectedDeck } }
        XCTAssertThrowsError(try OneTapRecords.save(key, store: store))
        XCTAssertTrue(store.data.matches.isEmpty)
        XCTAssertNil(OneTapRecords.sessions[key]?.saved)
        XCTAssertEqual(OneTapRecords.sessions[key]?.won, false)
        OneTapRecords.sessions.removeValue(forKey: key)
        try store.commit { $0.activeDeckID = nil }
        XCTAssertNoThrow(try OneTapRecords.begin(store))
    }
    @MainActor func testOneTapAllFourOutcomeCombinations() throws {
        let store = Store(inMemory: true)
        try store.commit { $0 = fixture() }
        for first in [true, false] {
            for won in [true, false] {
                let key = try OneTapRecords.begin(store)
                try OneTapRecords.selectOpponentClass(key, cardClass: .elf)
                try OneTapRecords.selectOutcome(key, first: first, won: won)
                try OneTapRecords.save(key, store: store)
                let match = try XCTUnwrap(store.data.matches.last)
                XCTAssertEqual(match.first, first)
                XCTAssertEqual(match.won, won)
                OneTapRecords.sessions.removeValue(forKey: key)
            }
        }
        XCTAssertEqual(store.data.matches.count, 4)
    }
    @MainActor func testOldBackupMigrationAndFixedDeck() throws {
        var old = fixture(); old.version = 1; old.activeDeckID = nil
        let migrated = try Store.decodeBackup(JSONEncoder().encode(old))
        XCTAssertEqual(migrated.version, 2)
        XCTAssertEqual(migrated.activeDeckID, old.lastDeckID)
        let store = Store(inMemory: true)
        try store.commit { $0 = migrated; $0.decks.append(Deck(name: "別デッキ", archetypeID: $0.archetypes[0].id)) }
        try store.saveMatch(Match(seasonID: migrated.currentSeasonID!, deckID: store.data.decks[1].id, opponentClass: nil, won: false, first: true))
        XCTAssertEqual(store.data.activeDeckID, migrated.activeDeckID)
        XCTAssertEqual(LiveRecords.content(store.data)?.losses, 0)
    }
    @MainActor func testStoredV1MigrationPreservesRecords() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "records.store")
        var old = fixture(); old.version = 1; old.activeDeckID = nil
        old.matches = [Match(seasonID: old.currentSeasonID!, deckID: old.decks[0].id, opponentClass: .dragon, won: true, first: false)]
        let container = try ModelContainer(for: LocalArchive.self, configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        let context = ModelContext(container)
        context.insert(LocalArchive(payload: try JSONEncoder().encode(old)))
        try context.save()
        let migrated = Store(storageURL: url)
        XCTAssertNil(migrated.loadError)
        XCTAssertEqual(migrated.data.version, 2)
        XCTAssertEqual(migrated.data.matches, old.matches)
        XCTAssertEqual(migrated.data.activeDeckID, old.lastDeckID)
        XCTAssertEqual(Store(storageURL: url).data, migrated.data)
    }
    func fixture() -> AppData {
        var data = AppData.fresh()
        let a = Archetype(name: "ランプ", cardClass: .dragon), b = Archetype(name: "フェイス", cardClass: .dragon)
        data.archetypes = [a,b]; data.decks = [Deck(name: "自分", archetypeID: a.id)]; data.lastDeckID = data.decks[0].id; data.activeDeckID = data.decks[0].id
        return data
    }
    func testStatsAndFirstSecond() {
        let d = fixture()
        let pairs = [(true,true,9),(false,true,4),(true,false,7),(false,false,8)]
        let matches = pairs.flatMap { won, first, count in (0..<count).map { _ in Match(seasonID: d.currentSeasonID!, deckID: d.decks[0].id, opponentClass: .dragon, won: won, first: first) } }
        let s = Stats(matches)
        XCTAssertEqual(s.count,28); XCTAssertEqual(s.wins,16); XCTAssertEqual(s.losses,12)
        XCTAssertEqual(s.rate!,57.142857,accuracy:0.0001); XCTAssertEqual(s.firstWins,9); XCTAssertEqual(s.firstLosses,4); XCTAssertEqual(s.secondWins,7); XCTAssertEqual(s.secondLosses,8)
        XCTAssertNil(Stats([]).rate)
    }
    func testSampleBoundaries() {
        XCTAssertEqual(Stats.sample(0),"未対戦")
        XCTAssertEqual(Stats.sample(1),Stats.sample(9)); XCTAssertNotEqual(Stats.sample(9),Stats.sample(10))
        XCTAssertEqual(Stats.sample(10),Stats.sample(29)); XCTAssertNotEqual(Stats.sample(29),Stats.sample(30))
    }
    func testSeasonIsolation() {
        var d = fixture(); let second = Season(name:"次"); d.seasons.append(second)
        d.matches = [Match(seasonID:d.currentSeasonID!,deckID:d.decks[0].id,opponentClass:.dragon,won:true,first:true), Match(seasonID:second.id,deckID:d.decks[0].id,opponentClass:.dragon,won:false,first:false)]
        XCTAssertEqual(d.filtered(d.currentSeasonID!.uuidString).count,1); XCTAssertEqual(d.filtered("all").count,2)
        XCTAssertEqual(Stats(d.filtered(second.id.uuidString)).rate,0)
    }
    func testWeightedOpinionAndMissingValue() throws {
        var d = fixture(); let deck = d.decks[0].id; let a = d.archetypes[0].id; let b = d.archetypes[1].id
        d.distributions = [Distribution(scope:"all",cardClass:.dragon,weights:[a.uuidString:70,b.uuidString:30])]
        d.opinions = [Opinion(scope:"all",deckID:deck,opponentID:a,percent:60),Opinion(scope:"all",deckID:deck,opponentID:b,percent:20)]
        try d.validate()
        XCTAssertEqual(Analysis.value(data:d,scope:"all",deck:deck,opponent:.cardClass(.dragon),source:.opinion).percent,48)
        XCTAssertNil(Analysis.value(data:d,scope:"all",deck:deck,opponent:.cardClass(.dragon),source:.actual).percent)
        XCTAssertNil(Analysis.value(data:d,scope:d.currentSeasonID!.uuidString,deck:deck,opponent:.cardClass(.dragon),source:.opinion).percent)
        d.opinions.removeLast()
        XCTAssertNil(Analysis.value(data:d,scope:"all",deck:deck,opponent:.cardClass(.dragon),source:.opinion).percent)
        d.distributions[0].weights = [a.uuidString:100,b.uuidString:0]
        XCTAssertEqual(Analysis.value(data:d,scope:"all",deck:deck,opponent:.cardClass(.dragon),source:.opinion).percent,60)
    }
    func testMinimumDoesNotInventMissingData() {
        XCTAssertEqual(Analysis.minimum([50,55]),50); XCTAssertEqual(Analysis.minimum([35,60]),35)
        XCTAssertEqual(Analysis.safer(50,35),0); XCTAssertNil(Analysis.safer(50,50)); XCTAssertNil(Analysis.safer(nil,35))
        XCTAssertNil(Analysis.minimum([nil,55])); XCTAssertEqual(Analysis.minimum([0,55]),0)
    }
    func testValidation() throws {
        var d=fixture(); try d.validate()
        d.opinions = [Opinion(scope:"all",deckID:d.decks[0].id,opponentID:d.archetypes[0].id,percent:0)]
        try d.validate(); d.opinions[0].percent=100; try d.validate()
        d.opinions[0].percent=101; XCTAssertThrowsError(try d.validate()); d.opinions=[]
        d.matches=[Match(seasonID:d.currentSeasonID!,deckID:d.decks[0].id,opponentClass:.elf,opponentID:d.archetypes[0].id,won:true,first:true)]
        XCTAssertThrowsError(try d.validate())
        d.matches=[]; d.archetypes.append(d.archetypes[0]); XCTAssertThrowsError(try d.validate())
    }
    @MainActor func testBackupRoundTripAndInvalidInput() throws {
        let d=fixture(); let bytes=try JSONEncoder().encode(d)
        XCTAssertEqual(try Store.decodeBackup(bytes),d)
        XCTAssertThrowsError(try Store.decodeBackup(Data("bad json".utf8)))
        var future=d; future.version=99
        XCTAssertThrowsError(try Store.decodeBackup(JSONEncoder().encode(future)))
    }
    @MainActor func testStoreTransactionsAndDeduplication() throws {
        let store=Store(inMemory:true); let d=fixture(); try store.commit { $0=d }
        let match=Match(seasonID:d.currentSeasonID!,deckID:d.decks[0].id,opponentClass:.dragon,won:true,first:true)
        try store.recordOnce(match); try store.recordOnce(match); XCTAssertEqual(store.data.matches.count,1)
        var edited=match; edited.won=false; edited.note="修正"; try store.saveMatch(edited)
        XCTAssertFalse(store.data.matches[0].won)
        let previous=store.data
        XCTAssertThrowsError(try store.commit { $0.currentSeasonID=UUID() })
        XCTAssertEqual(store.data,previous)
        let decoded=try Store.decodeBackup(store.export()); XCTAssertEqual(decoded,store.data)
        try store.commit { $0.matches.removeAll() }; XCTAssertTrue(store.data.matches.isEmpty)
    }
    @MainActor func testDraftValidationAndCancellation() throws {
        let store=Store(inMemory:true); try store.commit { $0=fixture() }
        let key=try QuickSessions.begin(store:store)
        XCTAssertThrowsError(try QuickSessions.match(key,store:store))
        QuickSessions.drafts[key]?.cardClass = .dragon
        QuickSessions.drafts[key]?.opponentChosen = true
        QuickSessions.drafts[key]?.result = 3
        let match=try QuickSessions.match(key,store:store)
        XCTAssertFalse(match.won); XCTAssertFalse(match.first)
        QuickSessions.drafts.removeValue(forKey:key)
        XCTAssertTrue(store.data.matches.isEmpty)
        XCTAssertThrowsError(try QuickSessions.match(key,store:store))
    }
    @MainActor func testPersistenceAcrossStoreInstances() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let url = folder.appending(path: "records.store")
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = Store(storageURL: url)
        XCTAssertNil(first.loadError)
        let expected = fixture()
        try first.commit { $0 = expected }
        let second = Store(storageURL: url)
        XCTAssertNil(second.loadError)
        var bootstrapped = expected; bootstrapped.ensureQuickEntryDefaults()
        XCTAssertEqual(second.data, bootstrapped)
    }
    func testWeightedActualAndSparseCoverage() {
        var d = fixture(); let deck = d.decks[0].id
        let a = d.archetypes[0].id, b = d.archetypes[1].id
        d.distributions = [Distribution(scope: "all", cardClass: .dragon, weights: [a.uuidString: 70, b.uuidString: 30])]
        d.matches = [Match(seasonID: d.currentSeasonID!, deckID: deck, opponentClass: .dragon, opponentID: a, won: true, first: true)]
        XCTAssertNil(Analysis.value(data: d, scope: "all", deck: deck, opponent: .cardClass(.dragon), source: .actual).percent)
        d.matches.append(Match(seasonID: d.currentSeasonID!, deckID: deck, opponentClass: .dragon, opponentID: b, won: false, first: false))
        let value = Analysis.value(data: d, scope: "all", deck: deck, opponent: .cardClass(.dragon), source: .actual)
        XCTAssertEqual(value.percent, 70); XCTAssertEqual(value.sampleCount, 1)
    }
    @MainActor func testRestoreAndRecoveryBackup() throws {
        let store = Store(inMemory: true); let before = store.data
        let replacement = fixture(); let backup = try store.restore(replacement)
        defer { try? FileManager.default.removeItem(at: backup) }
        XCTAssertEqual(store.data, replacement)
        XCTAssertEqual(try Store.decodeBackup(Data(contentsOf: backup)), before)
        var invalid = replacement; invalid.decks[0].archetypeID = UUID()
        XCTAssertThrowsError(try store.restore(invalid))
        XCTAssertEqual(store.data, replacement)
    }

    @MainActor func testIntentButtonsUpdateLiveDraft() async throws {
        let store = Store.shared; let original = store.data
        try store.commit { $0 = fixture() }
        defer { try? store.commit { $0 = original } }
        let key = try QuickSessions.begin(store: store)
        defer { QuickSessions.drafts.removeValue(forKey: key) }
        _ = try await RecordSnippet(session: key).perform()
        _ = try await UpdateQuickInput(session: key, operation: "class", value: "dragon").perform()
        XCTAssertEqual(QuickSessions.drafts[key]?.stage, 1)
        _ = try await UpdateQuickInput(session: key, operation: "archetype", value: store.data.archetypes[0].id.uuidString).perform()
        _ = try await UpdateQuickInput(session: key, operation: "result", value: "2").perform()
        _ = try await RecordSnippet(session: key).perform()
        let match = try QuickSessions.match(key, store: store)
        XCTAssertEqual(match.opponentID, store.data.archetypes[0].id)
        XCTAssertTrue(match.won); XCTAssertFalse(match.first)
        try store.recordOnce(match); try store.recordOnce(match)
        XCTAssertEqual(store.data.matches.count, 1)
        _ = try await UpdateQuickInput(session: key, operation: "class", value: "elf").perform()
        XCTAssertThrowsError(try QuickSessions.match(key, store: store))
    }

}
