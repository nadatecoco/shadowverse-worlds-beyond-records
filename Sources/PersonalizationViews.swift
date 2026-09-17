import SwiftUI

struct InputSetupView: View {
    var body: some View {
        List {
            Section {
                NavigationLink { InputSetupGuide(backTap: false) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Action Buttonで使う【推奨】").font(.headline)
                        Text("iPhone側面のボタン長押しで、小さい入力画面を表示します").font(.subheadline)
                    }
                }
                NavigationLink { ControlSetupGuide() } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Control Centerで使う").font(.headline)
                        Text("右上からスワイプして戦績入力を起動できます").font(.subheadline)
                    }
                }
                NavigationLink("背面タップで使う") { InputSetupGuide(backTap: true) }
            } footer: {
                Text("Action ButtonがないiPhoneでは、Control Centerをおすすめします。")
            }
        }.navigationTitle("高速入力を設定")
    }
}
struct InputSetupGuide: View {
    let backTap: Bool
    var body: some View {
        List {
            if backTap {
                Section("Control Centerをおすすめします") {
                    Text("背面タップは追加設定が必要です。このアプリの操作を直接選べることは確認できていないため、高速入力にはControl Centerをおすすめします。")
                    NavigationLink("Control Centerで使う") { ControlSetupGuide() }
                }
                Section("背面タップの設定場所") {
                    Text("ホーム画面の⚙️設定 → アクセシビリティ → タッチ → 背面タップ")
                    Text("iOSでは保存済みのショートカットを割り当てられます。このアプリを使うために新規作成する必要はありません。")
                }
            } else {
                Section {
                    Text("Shortcutsアプリでショートカットを作成する必要はありません。このアプリに最初から登録されています。")
                }
                Section("この4ステップで設定") {
                    Label("ホーム画面から⚙️設定を開く", systemImage: "1.circle")
                    Label("「アクションボタン」を選択", systemImage: "2.circle")
                    Label("左右に移動して「ショートカット」を選択", systemImage: "3.circle")
                    Label("「ショートカットを選択」→ このアプリの「戦績を記録」を選択", systemImage: "4.circle")
                }
                Section("設定したら") {
                    Text("iPhone側面のアクションボタンを長押し → 小さい入力画面 → 勝敗・先後を1回タップ → 保存")
                    Text("画面内の選択肢は普通にタップします。4つの勝敗・先後ボタンから1回タップすると保存されます。相手は不明で記録し、履歴から補完できます。画面を閉じる操作は別です。")
                }
                Section("設定が見つからない場合") {
                    Text("設定の検索欄で「アクションボタン」を検索してください。対応ボタンがないiPhoneではControl Centerを使います。")
                    Text("このアプリからアクションボタン専用の設定画面へ直接移動することはできません。")
                }
            }
        }.navigationTitle(backTap ? "背面タップ" : "Action Button")
    }
}
struct ControlSetupGuide: View {
    var body: some View {
        List {
            Section {
                Text("本体アプリの高速入力画面が直接開きます。小さい入力画面とは別の入口です。")
            }
            Section("追加する") {
                Text("右上から下へスワイプ → 空いた場所を長押し → コントロールを追加 →「シャドバ戦績研究」の「戦績入力」を選択")
                Text("ホームボタン搭載iPhoneでは、画面の下端から上へスワイプします。")
            }
            Section("使う") {
                Text("Control Centerを開く →「戦績入力」をタップ → 相手と勝敗・先後を選択 → 保存")
            }
            Section("その他の置き場所") {
                Text("ロック画面：長押し → カスタマイズ → ロック画面 → 下部のボタンを変更 → 戦績入力。入力にはロック解除が必要です。")
                Text("Action Buttonの補助経路：設定 → アクションボタン → コントロール → 戦績入力。本体アプリが開きます。")
            }
        }.navigationTitle("Control Center")
    }
}
struct ClassIconsEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var icons: [String: String] = [:]
    @State private var error: String?
    private var valid: Bool { CardClass.allCases.allSatisfy { AppData.validIcon(icons[$0.rawValue] ?? $0.defaultIcon) } }
    var body: some View {
        Form {
            Section {
                ForEach(CardClass.allCases) { cardClass in
                    HStack {
                        Text(cardClass.name)
                        Spacer()
                        TextField(cardClass.defaultIcon, text: Binding(get: { icons[cardClass.rawValue] ?? cardClass.defaultIcon }, set: { icons[cardClass.rawValue] = $0 }))
                            .multilineTextAlignment(.trailing).frame(width: 90)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                            .accessibilityLabel(cardClass.name + "のアイコン")
                    }
                }
            } footer: {
                Text("絵文字を1つ入力してください。キーボードの絵文字キーで選べます。保存すると本体と高速入力の両方に反映します。クラス名・戦績は変わりません。")
            }
            Button("標準のアイコンに戻す") { icons = [:] }
            if !valid { Text("各クラスの絵文字を1つずつ指定してください。").foregroundStyle(.red) }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("クラスアイコン")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do {
                            try store.commit { $0.classIcons = icons.filter { key, value in CardClass(rawValue: key)?.defaultIcon != value } }
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(!valid)
                }
            }
            .onAppear { icons = store.data.classIcons ?? [:] }
    }
}
