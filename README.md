# CaptionFlow

**A native macOS app for English-to-Simplified-Chinese live captions.**

[简体中文](README.zh-CN.md)

> Status: under active development. The repository currently contains the SwiftUI foundation, secure LLM settings, and the initial local-ASR integration work.

## What it is

CaptionFlow is designed for people following English videos, livestreams, podcasts, and meetings on Apple Silicon Macs. It will transcribe English locally, send only the transcript text to an LLM endpoint you configure, and show revisable Chinese live subtitles.

## Privacy model

- Raw microphone and system audio are processed locally and are never saved.
- Only transcribed English text and your translation instruction are sent to the selected LLM endpoint.
- API keys are stored in the macOS Keychain, not in UserDefaults or exported history.
- Captions and translations remain local and can later be exported as UTF-8 text.

## Planned flow

1. Configure an OpenAI-compatible endpoint, model, translation instruction, and API key.
2. Choose Microphone or System Audio and grant only the matching macOS permission.
3. CaptionFlow creates provisional English and Chinese lines, then revises the newest line as context improves.
4. Finalized captions stay in local session history.

## Current implementation

- SwiftUI macOS app target, minimum macOS 14.
- `Caption` domain model and session-state contract.
- HTTPS-only OpenAI-compatible LLM configuration screen.
- Keychain-backed API key persistence.
- WhisperKit `v1.1.0` dependency pinned for Apple Silicon local ASR.
- Unit tests for caption identity, keychain storage, LLM validation, and transcript normalization.

## Requirements

- Apple Silicon Mac
- macOS 14 Sonoma or later
- Xcode 16 or later (Xcode 27 is used by this project)

## Installation

```bash
git clone https://github.com/HuangChenning/captionflow.git
cd captionflow
xcodegen generate
xcodebuild test -scheme CaptionFlow -destination 'platform=macOS'
```

## Limitations

The first release supports English-to-Simplified-Chinese only. It intentionally excludes recording/replay, browser extensions, individual-app audio capture, accounts, billing, speaker diarization, and automatic model failover.

The app is not yet ready for end-user live transcription. Audio capture, model preparation, translation requests, the subtitle overlay, and session history are still being implemented.

## License

License selection is pending.
