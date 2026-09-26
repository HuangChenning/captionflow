import AppKit
import SwiftUI

/// 悬浮字幕窗的外观与显示设置（UserDefaults 键）。
enum CaptionOverlaySettings {
    static let translationFontSizeKey = "overlay.translationFontSize"
    static let originalFontSizeKey = "overlay.originalFontSize"
    static let showsOriginalKey = "overlay.showsOriginal"
    static let textColorKey = "overlay.textColor"
    static let backgroundOpacityKey = "overlay.backgroundOpacity"
    static let alwaysOnTopKey = "overlay.alwaysOnTop"
    static let hidesOnStopKey = "overlay.hidesOnStop"

    static let defaultTranslationFontSize = 28.0
    static let defaultOriginalFontSize = 17.0
    static let defaultBackgroundOpacity = 0.75
}

enum CaptionTextColor: String, CaseIterable, Identifiable {
    case white, yellow, cyan

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .white: return "白色"
        case .yellow: return "黄色"
        case .cyan: return "青色"
        }
    }

    var color: Color {
        switch self {
        case .white: return .white
        case .yellow: return Color(red: 1.0, green: 0.86, blue: 0.3)
        case .cyan: return Color(red: 0.45, green: 0.9, blue: 1.0)
        }
    }
}

/// 管理置顶、可拖动、无边框的悬浮字幕窗。
@MainActor
final class CaptionOverlayWindowController {
    private let panel: NSPanel

    init<Content: View>(rootView: Content) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 140),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 320, height: 80)
        panel.contentView = NSHostingView(rootView: rootView)

        if !panel.setFrameUsingName("CaptionOverlay") {
            place(on: NSScreen.main)
        }
        panel.setFrameAutosaveName("CaptionOverlay")
        applyLevel()

        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyLevel() }
        }
    }

    var isVisible: Bool { panel.isVisible }

    func show() { panel.orderFrontRegardless() }

    func hide() { panel.orderOut(nil) }

    func toggle() { isVisible ? hide() : show() }

    func moveToNextScreen() {
        let screens = NSScreen.screens
        guard screens.count > 1 else { return }
        let currentIndex = panel.screen.flatMap { screens.firstIndex(of: $0) } ?? 0
        place(on: screens[(currentIndex + 1) % screens.count])
    }

    /// 放到屏幕底部居中，与视频字幕的常见位置一致。
    private func place(on screen: NSScreen?) {
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 80))
    }

    private func applyLevel() {
        let alwaysOnTop = UserDefaults.standard.object(forKey: CaptionOverlaySettings.alwaysOnTopKey) as? Bool ?? true
        panel.level = alwaysOnTop ? .floating : .normal
    }
}

struct CaptionOverlayView: View {
    @ObservedObject var session: CaptionSessionController
    @AppStorage(CaptionOverlaySettings.backgroundOpacityKey) private var backgroundOpacity = CaptionOverlaySettings.defaultBackgroundOpacity

    var body: some View {
        Group {
            if let pipeline = session.pipeline {
                CaptionOverlayContent(pipeline: pipeline, notice: session.translationNotice)
            } else {
                OverlayHint(text: session.isPreparing ? "准备中…" : session.errorMessage ?? "字幕已停止")
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.1).opacity(backgroundOpacity))
        )
    }
}

private struct CaptionOverlayContent: View {
    @ObservedObject var pipeline: CaptionPipeline
    let notice: String?
    @AppStorage(CaptionOverlaySettings.translationFontSizeKey) private var translationFontSize = CaptionOverlaySettings.defaultTranslationFontSize
    @AppStorage(CaptionOverlaySettings.originalFontSizeKey) private var originalFontSize = CaptionOverlaySettings.defaultOriginalFontSize
    @AppStorage(CaptionOverlaySettings.showsOriginalKey) private var showsOriginal = true
    @AppStorage(CaptionOverlaySettings.textColorKey) private var textColorRaw = CaptionTextColor.white.rawValue

    private var textColor: Color {
        (CaptionTextColor(rawValue: textColorRaw) ?? .white).color
    }

    var body: some View {
        if let caption = pipeline.captions.last {
            VStack(spacing: 6) {
                if showsOriginal {
                    Text(caption.english)
                        .font(.system(size: originalFontSize))
                        .foregroundStyle(textColor.opacity(0.75))
                }
                // 译文未到时显示“…”；只显示英文时没有译文，不显示这一行。
                if caption.chinese != nil || caption.isProvisional {
                    Text(caption.chinese ?? "…")
                        .font(.system(size: translationFontSize, weight: .semibold))
                        .foregroundStyle(textColor)
                } else if let translationError = pipeline.translationError {
                    OverlayHint(text: "翻译失败，仅显示英文：\(translationError)")
                }
            }
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
        } else if case .failed = pipeline.state {
            OverlayHint(text: "字幕已中断")
        } else {
            OverlayHint(text: notice.map { "等待语音…\n\($0)" } ?? "等待语音…")
        }
    }
}

private struct OverlayHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 17))
            .foregroundStyle(.white.opacity(0.6))
    }
}
