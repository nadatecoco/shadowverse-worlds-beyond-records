import Foundation
import SwiftData
import Observation

// A versioned local aggregate: one SwiftData transaction replaces the complete small personal dataset.
// Value types keep calculations, backup validation and rollback independent of UI / ModelContext.
@Model final class LocalArchive {
    @Attribute(.unique) var key: String
    var payload: Data
    init(payload: Data) { self.key = "primary"; self.payload = payload }
}
@MainActor @Observable final class Store {
    static let shared = Store()
    private(set) var data = AppData.fresh()
    private(set) var loadError: String?
    private var context: ModelContext?
    private var archive: LocalArchive?
    var error: String?
    var showQuickEntry = false
    private let publishesLive: Bool
    init(inMemory: Bool = false, storageURL: URL? = nil) {
        publishesLive = !inMemory && storageURL == nil
        do {
            if !inMemory {
                let directory = storageURL?.deletingLastPathComponent() ?? URL.applicationSupportDirectory
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            let configuration = storageURL.map { ModelConfiguration(url: $0, cloudKitDatabase: .none) }
                ?? ModelConfiguration(isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
            let container = try ModelContainer(for: LocalArchive.self, configurations: configuration)
            context = ModelContext(container); context?.autosaveEnabled = false
            if let existing = try context?.fetch(FetchDescriptor<LocalArchive>()).first {
                data = try JSONDecoder().decode(AppData.self, from: existing.payload)
                if data.version < 3 {
                    if !inMemory {
                        let folder = URL.documentsDirectory.appending(path: "移行前バックアップ")
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        try existing.payload.write(to: folder.appending(path: "戦績_v1_\(UUID().uuidString).json"), options: .atomic)
                    }
                    try data.migrate()
                    try data.validate()
                    existing.payload = try JSONEncoder().encode(data)
                    try context?.save()
                }
                if data.ensureQuickEntryDefaults() {
                    try data.validate()
                    existing.payload = try JSONEncoder().encode(data)
                    try context?.save()
                }
                try data.validate(); archive = existing
            } else {
                data.ensureQuickEntryDefaults()
                let fresh = LocalArchive(payload: try JSONEncoder().encode(data))
                context?.insert(fresh); try context?.save(); archive = fresh
            }
        } catch { loadError = error.localizedDescription }
    }
    func commit(_ mutation: (inout AppData) throws -> Void) throws {
        guard loadError == nil, let context, let archive else { throw AppError.message(loadError ?? "保存先を開けません。") }
        var next = data; try mutation(&next); try next.validate()
        let encoded = try JSONEncoder().encode(next)
        do { archive.payload = encoded; try context.save(); data = next
            if publishesLive { LiveRecords.shared.refresh(data) } }
        catch { context.rollback(); throw error }
    }
    func perform(_ mutation: (inout AppData) throws -> Void) {
        do { try commit(mutation) } catch { self.error = error.localizedDescription }
    }
    func saveMatch(_ match: Match) throws {
        try commit { value in
            if let index = value.matches.firstIndex(where: { $0.id == match.id }) { value.matches[index] = match }
            else { value.matches.append(match) }
            value.lastDeckID = match.deckID
        }
    }
    func recordOnce(_ match: Match) throws {
        guard !data.matches.contains(where: { $0.id == match.id }) else { return }
        try saveMatch(match)
    }
    func prepareQuickEntry() throws {
        if !data.ensureQuickEntryDefaults() { return }
        try commit { $0.ensureQuickEntryDefaults() }
    }
    func export() throws -> Data {
        guard loadError == nil else { throw AppError.message("保存データを読み込めないため出力できません。") }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(data)
    }
    static func decodeBackup(_ bytes: Data) throws -> AppData {
        guard bytes.count <= 50_000_000 else { throw AppError.message("ファイルが大きすぎます（上限50MB）。") }
        var decoded = try JSONDecoder().decode(AppData.self, from: bytes); try decoded.migrate(); try decoded.validate(); return decoded
    }
    func restore(_ replacement: AppData) throws -> URL {
        try replacement.validate()
        let directory = URL.documentsDirectory.appending(path: "復元前バックアップ")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "復元前_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(6)).json")
        try export().write(to: url, options: .atomic)
        try commit { $0 = replacement }; return url
    }
    func addExamples() {
        let examples: [(CardClass, [String])] = [(.elf, ["ダストデイズエルフ"]), (.witch, ["魔手ウィッチ"]), (.nightmare, ["ミッドレンジナイトメア", "アグロナイトメア"]), (.bishop, ["アミュレットビショップ"]), (.dragon, ["ランプドラゴン", "フェイスドラゴン"]), (.nemesis, ["進化ネメシス", "AFネメシス"])]
        perform { data in
            for (cardClass, names) in examples { for name in names where !data.archetypes.contains(where: { $0.name == name && $0.cardClass == cardClass }) {
                data.archetypes.append(Archetype(name: name, cardClass: cardClass))
            } }
        }
    }
}
