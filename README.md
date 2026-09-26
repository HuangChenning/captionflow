<img src="assets/readme/hero.svg" width="100%" alt="CaptionFlow: English speech is recognized locally on the Mac, translated by an LLM, and shown as a live caption with the English line above its Chinese translation.">

[简体中文](README.zh-CN.md) · [Download](https://github.com/HuangChenning/captionflow/releases/latest) · [Releases](https://github.com/HuangChenning/captionflow/releases)

![Code size](https://img.shields.io/github/languages/code-size/HuangChenning/captionflow) ![Lines of code](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/HuangChenning/captionflow/badges/loc.json&cacheSeconds=3600)

CaptionFlow is a macOS app that shows live translated captions for English audio: videos, livestreams, podcasts, and online meetings. Speech is recognized on your Mac, and the English text is translated by an LLM you configure, so you read the meaning while people are still talking.

## What it does

| Area | What you get |
| --- | --- |
| Audio sources | Microphone, all system audio, or the audio of one app |
| Menu bar | Start/stop, audio source, target language, and settings from one menu bar icon |
| Caption window | Floating, draggable, resizable window that stays on top; font size, color, and background opacity are adjustable, and it can show the last 1–5 captions |
| Shortcuts | Customizable global shortcuts; defaults are ⌃⌥S start/stop, ⌃⌥H show/hide the caption window, ⌃⌥M move it to the next screen, ⌃⌥A switch audio source |
| Speech recognition | WhisperKit `base.en`, English only, runs locally |
| Translation | Your LLM (Anthropic or OpenAI-compatible), with Apple Translation shown first; or local-only / LLM-only modes |
| Target languages | Simplified Chinese, Traditional Chinese, Japanese, Korean, Spanish, French, German, Russian, Portuguese, Arabic |
| Models | Multiple saved model profiles; add, edit, delete, and test each one |
| Updates | Automatic update checks via Sparkle and GitHub Releases |

## How it works

<img src="assets/readme/how-it-works.svg" width="100%" alt="Four stages: capture microphone or system audio, recognize English with WhisperKit on the Mac, translate with an LLM API or Apple Translation as a fallback, and display bilingual live captions in a floating window.">

1. **Capture**: listen to the microphone, to everything your Mac plays (System Audio), or to a single app. Audio is never written to disk.
2. **Recognize**: [WhisperKit](https://github.com/argmaxinc/WhisperKit) turns English speech into text on your Mac.
3. **Translate**: the English text is sent to your LLM endpoint (Anthropic Messages or OpenAI-compatible API). Apple's on-device Translation shows a line first, and the LLM result replaces it when it arrives; if the LLM fails, the local line stays.
4. **Display**: a floating caption window shows the latest English line with its translation above other apps, and keeps revising it as more context comes in.

## Quick start

1. Download the latest `CaptionFlow-x.y.z.zip` from [Releases](https://github.com/HuangChenning/captionflow/releases/latest) and move `CaptionFlow.app` to Applications.
2. The app is not notarized yet. On first launch, right-click `CaptionFlow.app` → **Open**, then confirm.
3. Open **Settings → 模型** (Models), click **添加模型** (Add Model), and enter the API style, base URL, model name, and API key. Click **测试连接** (Test Connection) to check it. The app UI is currently in Chinese.
4. CaptionFlow has no main window; its controls live in the menu bar (clicking the Dock icon opens Settings). Click the menu bar icon, pick 麦克风 (Microphone), 全部系统音频 (all system audio), or a single app under **音频源** (Audio Source), then click **开启实时字幕** (Start Live Captions). macOS asks for the matching permission (microphone, or screen and system audio recording). Captions appear in a floating window at the bottom of the screen; drag it anywhere, and adjust it under **Settings → 文本外观** (Text Appearance) and **显示设置** (Display).

The first start downloads the WhisperKit English model, so it takes longer than later starts. After that, CaptionFlow updates itself through Sparkle; you can also check manually from **CaptionFlow → 检查更新…** (Check for Updates) or **Settings → 软件更新** (Software Update).

## Privacy

- Raw microphone and system audio stay on your Mac and are never saved.
- Only the recognized English text and your translation instruction go to the LLM endpoint you configure. In local-only mode nothing leaves the Mac.
- API keys are stored in the macOS Keychain, not in UserDefaults.

## Requirements

- Apple Silicon Mac
- macOS 15 Sequoia or later

## Build from source

Requires Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
git clone https://github.com/HuangChenning/captionflow.git
cd captionflow
xcodegen generate
xcodebuild -scheme CaptionFlow -destination 'platform=macOS' build
xcodebuild test -scheme CaptionFlow -destination 'platform=macOS'
```

## Limitations

- The spoken language must be English.
- No session history or export yet.
- Builds are ad-hoc signed, not notarized, so macOS shows a warning on first launch.

## License

License selection is pending.
