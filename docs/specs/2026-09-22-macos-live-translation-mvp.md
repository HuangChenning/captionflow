# CaptionFlow: macOS English-to-Chinese Live Translation MVP

## Goal

Build CaptionFlow, a native macOS app that captures microphone or system audio, transcribes English locally, sends only incremental transcript text to a user-configured LLM, and displays revisable Simplified Chinese live subtitles.

## Users and jobs

The initial users are people following English video, livestream, podcast, and online-meeting audio. They need understandable Chinese subtitles without uploading their original audio or relying on a browser extension.

## Product decisions

- Target Apple Silicon Macs only; minimum macOS 14 Sonoma.
- Support microphone and all-system audio. Do not support an individual-app picker in the MVP.
- Use local English ASR. The app downloads its one recommended model after first-run consent; the application bundle does not include it.
- Translate only English speech to Simplified Chinese.
- Provide low-latency provisional subtitles. The most recent subtitle may be revised as later context arrives; committed history is immutable.
- Preserve raw audio nowhere. Keep transcript/translation history locally only; export it as UTF-8 `.txt`.
- Send only transcribed English text to the selected LLM endpoint. API keys are kept in Keychain.
- Include known provider presets plus a custom OpenAI-compatible base URL, model, and key.
- Show a floating, draggable, always-on-top subtitle panel. Default to English plus Chinese; offer Chinese-only, font-size, opacity, and pin controls.
- If translation fails, keep English transcription running and show a visible translation-status error for the affected line.
- Provide one editable instruction/terminology text field. Its default asks for natural, accurate, concise Simplified Chinese simultaneous-interpretation subtitles.
- Save local session history and support `.txt`, but not `.srt`, export.
- Do not build accounts, billing, recording/replay, speaker diarization, summaries, browser extensions, individual-app capture, other language pairs, or automatic model failover.

## Privacy and permissions

- Request microphone permission only when microphone mode is selected.
- Request macOS Screen Recording permission only when system-audio mode is selected, using ScreenCaptureKit. Do not record or retain video frames.
- Clearly disclose the selected LLM endpoint before the first request and in Settings.
- API keys and persisted history remain on the device. A user can delete a session from History.

## Architecture

The app is Swift + SwiftUI. `Capture` produces normalized PCM; `ASR` converts rolling audio windows to English transcript updates; `Translation` coalesces updates and calls an OpenAI-compatible chat-completions endpoint; `Sessions` owns the state machine and immutable committed entries; `Presentation` renders the floating panel and settings.

Use ScreenCaptureKit for system audio (`SCStreamConfiguration.capturesAudio = true`) and AVFoundation for microphone capture. Evaluate and integrate `whisper.cpp` through its maintained Swift Package during the ASR spike; do not write custom C++ bindings unless the package cannot meet the required interface.

## UX flow

1. On first launch, choose/download the English ASR model and enter an LLM configuration.
2. Choose Microphone or System Audio, grant only the matching permission, then press Start.
3. Show provisional English/Chinese lines in the subtitle panel; update provisional lines in place.
4. Finalize lines into local history. On Stop, leave the session available for review/export/delete.

## MVP acceptance criteria

- A user can configure a valid compatible endpoint and key, select a capture source, and start a session without assistance.
- A microphone and a system-audio session both produce English transcript updates and Chinese subtitles.
- Normal English test material displays a Chinese provisional subtitle in three seconds or less for the majority of measured segments.
- Network/auth/rate-limit failures retain English captions and make the Chinese failure apparent.
- The app never writes raw audio to disk; API keys are absent from UserDefaults and exported text.
- On a 10-person, one-week closed beta, at least 6 testers use it again in a real meeting or media session.

## Distribution

Ship the beta as a Developer ID–signed and notarized `.dmg`. Keep diagnostics opt-in and local for beta; do not transmit diagnostics automatically.
