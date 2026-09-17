import XCTest
final class FlowTests: XCTestCase {
    @MainActor func testInAppFastInputPreview() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let launch = app.buttons["高速入力を試す"]
        XCTAssertTrue(launch.waitForExistence(timeout: 8))
        launch.tap()

        XCTAssertTrue(app.navigationBars["高速入力"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["自分"].exists)
        XCTAssertFalse(app.staticTexts["✅ 保存しました"].exists)

        app.buttons["🧙 ウィッチ"].tap()
        app.buttons["🟢 先攻勝ち"].tap()
        XCTAssertFalse(app.staticTexts["✅ 保存しました"].exists)

        app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["✅ 保存しました"].waitForExistence(timeout: 5))
        app.buttons["閉じる"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["履歴（1戦）"].waitForExistence(timeout: 5))
    }

    @MainActor func testControlOpensEntry() throws {
        dismissShortcutCompletion()
        XCUIDevice.shared.press(.home)
        let app = XCUIApplication(); app.launchArguments = []; app.launch()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        func openCenter() {
            system.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.01)).press(forDuration: 0.1, thenDragTo: system.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.7)))
        }
        openCenter()
        let control = system.descendants(matching: .any).matching(identifier: "戦績入力").firstMatch
        if !control.waitForExistence(timeout: 2) {
            XCTAssertTrue(system.buttons["コントロールを追加"].waitForExistence(timeout: 5))
            system.buttons["コントロールを追加"].tap()
            system.buttons["コントロールを追加"].tap()
            system.searchFields["コントロールを検索"].tap()
            system.searchFields["コントロールを検索"].typeText("戦績")
            XCTAssertTrue(system.buttons["戦績入力"].waitForExistence(timeout: 5))
            system.buttons["戦績入力"].tap()
        }
        XCUIDevice.shared.press(.home)
        app.terminate()
        openCenter()
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        control.tap()
        XCTAssertTrue(app.navigationBars["戦績を記録"].waitForExistence(timeout: 10))
        snapshot("Controlから戦績入力")
        app.buttons["キャンセル"].tap()
    }
    @MainActor func testInputSetupAndIconSettings() throws {
        dismissShortcutCompletion()
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "⚡ 高速入力を設定")).firstMatch.waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "⚡ 高速入力を設定")).firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Action Buttonで使う【推奨】")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["この4ステップで設定"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertFalse(app.buttons["iPhoneの設定を開く"].exists)
        snapshot("Action Button設定案内")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["背面タップで使う"].tap()
        XCTAssertTrue(app.staticTexts["Control Centerをおすすめします"].waitForExistence(timeout: 5))
        app.tabBars.buttons["デッキ／設定"].tap()
        app.buttons["クラスアイコンを変更"].tap()
        XCTAssertTrue(app.textFields["エルフのアイコン"].waitForExistence(timeout: 5))
        snapshot("クラスアイコン設定")
        app.buttons["標準のアイコンに戻す"].tap()
        app.buttons["保存"].tap()
        XCTAssertTrue(app.navigationBars["デッキ／設定"].exists)
        app.buttons["⚡ 高速入力を設定"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Control Centerで使う")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Control Center"].waitForExistence(timeout: 5))
        snapshot("コントロール設定案内")
    }
    @MainActor func testRecordAndTabs() throws {
        dismissShortcutCompletion()
        let app=XCUIApplication(); app.launchArguments=["--ui-testing"]; app.launch()
        XCTAssertTrue(app.navigationBars["戦績"].waitForExistence(timeout:10))
        app.buttons["戦績を追加"].tap()
        app.buttons["🧚 エルフ"].tap()
        XCTAssertTrue(app.buttons["先攻勝利"].waitForExistence(timeout:5))
        app.buttons["先攻勝利"].tap(); app.buttons["保存"].tap()
        snapshot("戦績")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["履歴（1戦）"].waitForExistence(timeout:5))
        app.tabBars.buttons["相性表"].tap()
        XCTAssertTrue(app.navigationBars["相性表"].exists)
        snapshot("相性表")
        app.tabBars.buttons["持ち込み"].tap()
        XCTAssertTrue(app.navigationBars["持ち込み"].exists)
        snapshot("持ち込み")
        app.tabBars.buttons["デッキ／設定"].tap()
        snapshot("設定")
        app.swipeUp()
        XCTAssertTrue(app.buttons["JSONを書き出す"].waitForExistence(timeout:3))
    }
    @MainActor private func dismissShortcutCompletion() {
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for title in ["Done", "完了"] where system.buttons[title].exists { system.buttons[title].tap() }
    }
    @MainActor private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIApplication().screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor func testOpinionAndBO1Comparison() throws {
        dismissShortcutCompletion()
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        app.tabBars.buttons["相性表"].tap()
        app.buttons["ダストデイズエルフ 対 ダストデイズエルフ"].tap()
        XCTAssertTrue(app.navigationBars["相性の詳細"].waitForExistence(timeout: 5))
        app.buttons["保存"].tap()
        app.tabBars.buttons["持ち込み"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "デッキ1")).firstMatch.tap()
        app.buttons["ダストデイズエルフ"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "デッキ2")).firstMatch.tap()
        app.buttons["魔手ウィッチ"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "相手1")).firstMatch.tap()
        app.buttons["ダストデイズエルフ"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "相手2")).firstMatch.tap()
        app.buttons["魔手ウィッチ"].tap()
        XCTAssertTrue(app.staticTexts["✓ 安全候補：ダストデイズエルフ"].waitForExistence(timeout: 5))
        snapshot("持ち込み解析結果")
        app.buttons["📊 実戦"].tap()
        XCTAssertTrue(app.staticTexts["比較に必要な相性が不足しています。"].exists)
    }

    @MainActor func testShortcutRecordsAndPersists() throws {
        dismissShortcutCompletion()
        let app = XCUIApplication(); app.launchArguments = []; app.launch()
        app.swipeUp()
        let history = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "履歴（")).firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        let previousCount = Int(history.label.filter(\.isNumber)) ?? 0
        app.tabBars.buttons["デッキ／設定"].tap()
        app.buttons["アーキタイプの例を取り込む"].tap()
        app.buttons["自分のデッキ"].tap()
        if !app.staticTexts["検証用デッキ"].exists {
            app.buttons["追加"].tap()
            app.textFields["名前"].tap(); app.textFields["名前"].typeText("検証用デッキ")
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "アーキタイプ")).firstMatch.tap()
            app.buttons["ダストデイズエルフ"].tap()
            app.buttons["保存"].tap()
        }
        app.tabBars.buttons["戦績"].tap()
        app.swipeDown()
        let active = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "現在使用中")).firstMatch
        XCTAssertTrue(active.waitForExistence(timeout: 5))
        active.tap()
        app.buttons["検証用デッキ"].tap()
        if app.buttons["ライブ戦績を終了"].exists { app.buttons["ライブ戦績を終了"].tap() }
        app.buttons["ライブ戦績を開始"].tap()
        XCTAssertTrue(app.buttons["ライブ戦績を終了"].waitForExistence(timeout: 8))
        XCUIDevice.shared.press(.home)
        let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
        shortcuts.launch()
        if shortcuts.buttons["OK"].waitForExistence(timeout: 1) { shortcuts.buttons["OK"].tap() }
        let appShortcuts = shortcuts.staticTexts["シャドバ戦績研究"].firstMatch
        XCTAssertTrue(appShortcuts.waitForExistence(timeout: 5))
        appShortcuts.tap()
        let builtInRecord = shortcuts.staticTexts["戦績を記録"].firstMatch
        XCTAssertTrue(builtInRecord.waitForExistence(timeout: 5))
        builtInRecord.tap()
        let snippet = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(snippet.buttons["🟢 先攻勝ち"].waitForExistence(timeout: 10))
        let statsLabel = snippet.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "勝率")).firstMatch
        let beforeStats = statsLabel.label
        Thread.sleep(forTimeInterval: 1) // Wait for the system snippet animation before capturing evidence.
        let initial = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        initial.name = "1タップ入力"; initial.lifetime = .keepAlways; add(initial)
        snippet.staticTexts["🟢 先攻勝ち"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(snippet.staticTexts["保存しました"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.state == .runningForeground)
        XCTAssertNotEqual(statsLabel.label, beforeStats)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "1タップ保存とライブ表示"; attachment.lifetime = .keepAlways; add(attachment)
        dismissShortcutCompletion()
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1) // Wait for the Home transition before capturing Dynamic Island.
        let liveImage = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        liveImage.name = "保存後Dynamic Island"; liveImage.lifetime = .keepAlways; add(liveImage)
        app.activate()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["履歴（\(previousCount + 1)戦）"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["履歴（\(previousCount + 1)戦）"].waitForExistence(timeout: 5))
        app.swipeDown()
        if app.buttons["ライブ戦績を終了"].exists { app.buttons["ライブ戦績を終了"].tap() }
    }
}
