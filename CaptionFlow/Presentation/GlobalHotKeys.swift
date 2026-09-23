import AppKit
import Carbon.HIToolbox

/// 一个按键组合。modifiers 用 Carbon 掩码，可直接交给 RegisterEventHotKey。
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    /// 录制时记下的按键名称，例如 "S"、"F5"、"Space"。
    var keyLabel: String

    var displayString: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + keyLabel
    }

    /// 至少要有 ⌃、⌥ 或 ⌘，否则会吞掉其他应用里的正常打字。
    var hasRequiredModifier: Bool {
        modifiers & UInt32(controlKey | optionKey | cmdKey) != 0
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }
}

/// 全局快捷键动作。用 Carbon 热键注册，不需要辅助功能权限。
enum GlobalHotKey: String, CaseIterable, Identifiable {
    case toggleCaptions, toggleOverlay, moveOverlayToNextScreen, switchAudioSource

    static let enabledKey = "shortcuts.enabled"
    /// 设置页录制快捷键时发出，userInfo["isRecording"] 为 Bool；录制期间暂停全局热键，否则按下已注册的组合会被热键截走。
    static let recordingDidChangeNotification = Notification.Name("GlobalHotKey.recordingDidChange")

    var id: Self { self }

    var title: String {
        switch self {
        case .toggleCaptions: return "开始 / 停止字幕"
        case .toggleOverlay: return "显示 / 隐藏字幕窗"
        case .moveOverlayToNextScreen: return "字幕窗移到下一块屏幕"
        case .switchAudioSource: return "切换音频源（停止时）"
        }
    }

    var defaultCombo: KeyCombo {
        let modifiers = UInt32(controlKey | optionKey)
        switch self {
        case .toggleCaptions: return KeyCombo(keyCode: UInt32(kVK_ANSI_S), modifiers: modifiers, keyLabel: "S")
        case .toggleOverlay: return KeyCombo(keyCode: UInt32(kVK_ANSI_H), modifiers: modifiers, keyLabel: "H")
        case .moveOverlayToNextScreen: return KeyCombo(keyCode: UInt32(kVK_ANSI_M), modifiers: modifiers, keyLabel: "M")
        case .switchAudioSource: return KeyCombo(keyCode: UInt32(kVK_ANSI_A), modifiers: modifiers, keyLabel: "A")
        }
    }

    private var storageKey: String { "shortcuts.\(rawValue)" }

    func combo(in defaults: UserDefaults = .standard) -> KeyCombo {
        defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) } ?? defaultCombo
    }

    /// 传 nil 恢复默认。
    func setCombo(_ combo: KeyCombo?, in defaults: UserDefaults = .standard) {
        if let combo, combo != defaultCombo, let data = try? JSONEncoder().encode(combo) {
            defaults.set(data, forKey: storageKey)
        } else {
            defaults.removeObject(forKey: storageKey)
        }
    }

    /// 返回已占用该组合的其他动作。
    func conflict(with combo: KeyCombo, in defaults: UserDefaults = .standard) -> GlobalHotKey? {
        Self.allCases.first { $0 != self && $0.combo(in: defaults) == combo }
    }
}

@MainActor
final class GlobalHotKeys {
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?

    func register(_ bindings: [(combo: KeyCombo, action: () -> Void)]) {
        unregisterAll()
        installHandlerIfNeeded()
        for (index, binding) in bindings.enumerated() {
            let id = EventHotKeyID(signature: OSType(0x4346_4C57), id: UInt32(index + 1)) // "CFLW"
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                binding.combo.keyCode, binding.combo.modifiers, id,
                GetApplicationEventTarget(), 0, &ref
            )
            guard status == noErr, let ref else { continue }
            hotKeyRefs.append(ref)
            actions[id.id] = binding.action
        }
    }

    func unregisterAll() {
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
        actions.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            let hotKeys = Unmanaged<GlobalHotKeys>.fromOpaque(userData).takeUnretainedValue()
            // Carbon 在主线程派发热键事件。
            MainActor.assumeIsolated { hotKeys.actions[hotKeyID.id]?() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }
}
