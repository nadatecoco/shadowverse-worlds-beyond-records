import ActivityKit
import SwiftUI
import Observation

@MainActor @Observable final class LiveRecords {
    static let shared = LiveRecords()
    var running = false
    var message: String?
    private var pending: Task<Void, Never>?
    static func content(_ data: AppData) -> RecordActivity.ContentState? {
        guard let deck = data.activeDeck, let season = data.currentSeasonID else { return nil }
        let matches = data.filtered(season.uuidString, deckID: deck.id).sorted {
            $0.date == $1.date ? $0.id.uuidString > $1.id.uuidString : $0.date > $1.date
        }
        return .init(deckName: deck.name, seasonName: data.seasonName(season),
                     wins: matches.filter(\.won).count, losses: matches.filter { !$0.won }.count,
                     streak: matches.prefix(while: \.won).count)
    }
    func refresh(_ data: AppData) {
        let state = Self.content(data)
        let previous = pending
        pending = Task { @MainActor in
            await previous?.value
            for activity in Activity<RecordActivity>.activities {
                guard activity.activityState == .active || activity.activityState == .stale else { continue }
                if let state {
                    await activity.update(ActivityContent(state: state, staleDate: nil))
                } else {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
            self.running = Activity<RecordActivity>.activities.contains { $0.activityState == .active || $0.activityState == .stale }
        }
    }
    func flush() async { await pending?.value }
    func start(_ data: AppData) async {
        await flush()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            message = "ライブアクティビティが許可されていません。iPhoneの設定でこのアプリの許可を確認してください。"; return
        }
        guard let state = Self.content(data) else { message = "現在使用中のデッキを選んでください。"; return }
        do {
            if !Activity<RecordActivity>.activities.contains(where: { $0.activityState == .active || $0.activityState == .stale }) {
                _ = try Activity.request(attributes: RecordActivity(), content: ActivityContent(state: state, staleDate: nil), pushType: nil)
            }
            refresh(data); await flush(); message = nil
        } catch { message = error.localizedDescription }
    }
    func stop() async {
        let previous = pending
        let task = Task { @MainActor in
            await previous?.value
            for activity in Activity<RecordActivity>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
            self.running = false
        }
        pending = task
        await task.value
    }
}
struct LiveRecordSettings: View {
    @Environment(Store.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    private var live: LiveRecords { .shared }
    var body: some View {
        Section {
            Picker("現在使用中", selection: Binding(get: { store.data.activeDeck?.id }, set: { id in store.perform { $0.activeDeckID = id } })) {
                Text("選択してください").tag(nil as UUID?)
                ForEach(store.data.decks.filter { !$0.archived }) { Text($0.name).tag(Optional($0.id)) }
            }
            Button(live.running ? "ライブ戦績を終了" : "ライブ戦績を開始") {
                Task { if live.running { await live.stop() } else { await live.start(store.data) } }
            }.disabled(store.data.activeDeck == nil && !live.running)
            if let message = live.message { Text(message).font(.caption).foregroundStyle(.secondary) }
        } footer: {
            Text("高速入力はこのデッキ・現在環境に保存します。ライブ表示はOSの表示領域で、最長8時間です。")
        }
        .task { live.refresh(store.data); await live.flush() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { live.refresh(store.data) } }
    }
}
