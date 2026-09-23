import Carbon.HIToolbox
import XCTest
@testable import CaptionFlow

@MainActor
final class GlobalHotKeyTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "GlobalHotKeyTests")
        defaults.removePersistentDomain(forName: "GlobalHotKeyTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "GlobalHotKeyTests")
        super.tearDown()
    }

    func testCustomComboPersistsAndResetRestoresDefault() {
        // 用户改过的快捷键重启后要保留；「恢复默认」要真正回到默认组合。
        let custom = KeyCombo(keyCode: UInt32(kVK_F5), modifiers: UInt32(cmdKey), keyLabel: "F5")
        GlobalHotKey.toggleCaptions.setCombo(custom, in: defaults)
        XCTAssertEqual(GlobalHotKey.toggleCaptions.combo(in: defaults), custom)

        GlobalHotKey.toggleCaptions.setCombo(nil, in: defaults)
        XCTAssertEqual(GlobalHotKey.toggleCaptions.combo(in: defaults), GlobalHotKey.toggleCaptions.defaultCombo)
    }

    func testConflictIsReportedAgainstOtherActionOnly() {
        // 两个动作用同一组合时 Carbon 只会注册一个，另一个静默失效，所以录制时必须拦下。
        let overlayDefault = GlobalHotKey.toggleOverlay.defaultCombo
        XCTAssertEqual(GlobalHotKey.toggleCaptions.conflict(with: overlayDefault, in: defaults), .toggleOverlay)
        // 给动作重新录它自己当前的组合不算冲突。
        XCTAssertNil(GlobalHotKey.toggleOverlay.conflict(with: overlayDefault, in: defaults))
    }

    func testComboWithoutControlOptionOrCommandIsRejected() {
        // 只有 ⇧ 或没有修饰键的全局热键会吞掉其他应用里的正常输入。
        XCTAssertFalse(KeyCombo(keyCode: UInt32(kVK_ANSI_S), modifiers: 0, keyLabel: "S").hasRequiredModifier)
        XCTAssertFalse(KeyCombo(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(shiftKey), keyLabel: "S").hasRequiredModifier)
        XCTAssertTrue(KeyCombo(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey | shiftKey), keyLabel: "S").hasRequiredModifier)
    }

    func testDisplayStringUsesStandardModifierOrder() {
        let combo = KeyCombo(
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: KeyCombo.carbonModifiers(from: [.command, .shift, .option, .control]),
            keyLabel: "K"
        )
        XCTAssertEqual(combo.displayString, "⌃⌥⇧⌘K")
    }
}
