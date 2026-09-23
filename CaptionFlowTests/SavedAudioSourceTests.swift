import XCTest
@testable import CaptionFlow

final class SavedAudioSourceTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SavedAudioSourceTests")
        defaults.removePersistentDomain(forName: "SavedAudioSourceTests")
    }

    // 首次启动没有记录时用麦克风，不需要录屏权限。
    func testDefaultsToMicrophone() {
        XCTAssertEqual(SavedAudioSource.load(from: defaults), SavedAudioSource(kind: .microphone, appBundleID: nil))
    }

    // 授权录屏后必须重启 app，重启后应仍是上次选的单个应用，不用重选。
    func testSingleAppSourceSurvivesRelaunch() {
        let source = SavedAudioSource(kind: .systemAudio, appBundleID: "com.example.player")
        source.save(to: defaults)
        XCTAssertEqual(SavedAudioSource.load(from: defaults), source)
    }

    // 切回麦克风后，残留的应用 ID 不能被当成系统音频的选择恢复出来。
    func testMicrophoneIgnoresStaleAppBundleID() {
        defaults.set(AudioSourceKind.microphone.rawValue, forKey: SavedAudioSource.kindKey)
        defaults.set("com.example.player", forKey: SavedAudioSource.appBundleIDKey)
        XCTAssertEqual(SavedAudioSource.load(from: defaults), SavedAudioSource(kind: .microphone, appBundleID: nil))
    }
}
