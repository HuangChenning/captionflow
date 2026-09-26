# CaptionFlow MVP Implementation Plan

> **状态：已完成，仅作历史记录。** 这份计划中的功能已经实现，但部分做法与计划不同（例如语音识别使用 WhisperKit 而非 whisper.cpp）。下面未勾选的步骤不代表待办事项；当前功能以 README 为准，待办事项见 `docs/TODO.md`。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a signed-beta-ready native macOS app that locally transcribes microphone or system English audio and renders LLM-translated Simplified Chinese live subtitles.

**Architecture:** A SwiftUI shell owns an `AppSession` state machine. Capture adapters emit normalized PCM into a local ASR adapter; transcript updates feed a throttled translation coordinator; the presentation layer shows the one mutable provisional caption and committed caption history. Persistence is local, while endpoint secrets live exclusively in Keychain.

**Tech Stack:** Swift 5.9+, SwiftUI, AVFoundation, ScreenCaptureKit, Security/Keychain, URLSession, XCTest, `whisper.cpp` Swift Package (validated in Task 3).

**Spec:** `docs/specs/2026-09-22-macos-live-translation-mvp.md`

## Global Constraints

- Apple Silicon only; deployment target is macOS 14.0.
- English speech to Simplified Chinese is the only language pair.
- Capture sources are microphone and all-system audio only; never persist raw audio or frames.
- Use direct Developer ID beta distribution; no user accounts, billing, or in-app purchase.
- Store API keys only in Keychain; history is local and export format is UTF-8 `.txt`.
- The translation request must include only transcript text and the user instruction; never audio.
- Translation failure must not stop English transcription.

---

## Proposed file structure

```
CaptionFlow/
  CaptionFlowApp.swift
  Domain/Caption.swift
  Domain/AppSessionState.swift
  Capture/AudioCapture.swift
  Capture/MicrophoneCapture.swift
  Capture/SystemAudioCapture.swift
  ASR/EnglishASR.swift
  ASR/WhisperASR.swift
  Translation/LLMConfiguration.swift
  Translation/TranslationClient.swift
  Translation/TranslationCoordinator.swift
  Security/KeychainStore.swift
  Persistence/SessionStore.swift
  Presentation/SessionViewModel.swift
  Presentation/FloatingCaptionPanel.swift
  Presentation/MainWindowView.swift
  Presentation/SettingsView.swift
CaptionFlowTests/
  CaptionTests.swift
  TranslationCoordinatorTests.swift
  SessionViewModelTests.swift
  SessionStoreTests.swift
  KeychainStoreTests.swift
CaptionFlowIntegrationTests/
  CapturePermissionTests.swift
  TranslationClientTests.swift
docs/
  beta-test-script.md
```

### Task 1: Create the Xcode project and domain contracts

**Files:**
- Create: `CaptionFlow.xcodeproj`, `CaptionFlow/CaptionFlowApp.swift`, `CaptionFlow/Domain/Caption.swift`, `CaptionFlow/Domain/AppSessionState.swift`, `CaptionFlowTests/CaptionTests.swift`

**Interfaces:**
- Produces `Caption(id: UUID, english: String, chinese: String?, isProvisional: Bool, createdAt: Date)` and `AppSessionState` with `.idle`, `.requestingPermission`, `.running`, `.stopping`, `.failed(String)`.

- [ ] **Step 1: Create a macOS App Xcode project named `CaptionFlow`**

Set product bundle identifier to `com.taihongteng.CaptionFlow`, interface to SwiftUI, language to Swift, deployment target to macOS 14.0, and add a unit-test target named `CaptionFlowTests`.

- [ ] **Step 2: Write the failing caption value-semantics test**

```swift
func testReplacingProvisionalCaptionKeepsItsIdentity() {
    let id = UUID()
    let caption = Caption(id: id, english: "hello", chinese: "你好", isProvisional: true, createdAt: .now)
    XCTAssertEqual(caption.replacing(english: "hello world", chinese: "你好，世界").id, id)
}
```

- [ ] **Step 3: Run the test and confirm it fails because `Caption` is undefined**

Run: `xcodebuild test -scheme CaptionFlow -destination 'platform=macOS' -only-testing:CaptionFlowTests/CaptionTests`

- [ ] **Step 4: Implement the two domain types minimally**

```swift
struct Caption: Identifiable, Codable, Equatable {
    let id: UUID; var english: String; var chinese: String?; var isProvisional: Bool; let createdAt: Date
    func replacing(english: String, chinese: String?) -> Self { .init(id: id, english: english, chinese: chinese, isProvisional: true, createdAt: createdAt) }
}
```

- [ ] **Step 5: Re-run the test and commit**

Run: `xcodebuild test -scheme CaptionFlow -destination 'platform=macOS' -only-testing:CaptionFlowTests/CaptionTests`

Commit: `git add CaptionFlow.xcodeproj CaptionFlow CaptionFlowTests && git commit -m "feat: scaffold CaptionFlow app domain"`

### Task 2: Build local settings and Keychain-backed LLM configuration

**Files:**
- Create: `CaptionFlow/Translation/LLMConfiguration.swift`, `CaptionFlow/Security/KeychainStore.swift`, `CaptionFlow/Presentation/SettingsView.swift`, `CaptionFlowTests/KeychainStoreTests.swift`

**Interfaces:**
- Produces `LLMConfiguration(baseURL: URL, model: String, instruction: String)` and `KeychainStore.save(secret:for:)`, `secret(for:)`, `deleteSecret(for:)`.

- [ ] **Step 1: Write failing Keychain round-trip and deletion tests**

```swift
func testSecretCanBeReadThenDeleted() throws {
    let store = KeychainStore(service: "com.taihongteng.CaptionFlow.tests")
    try store.save(secret: "test-key", for: "openai")
    XCTAssertEqual(try store.secret(for: "openai"), "test-key")
    try store.deleteSecret(for: "openai")
    XCTAssertNil(try store.secret(for: "openai"))
}
```

- [ ] **Step 2: Run the Keychain test and confirm it fails**

Run: `xcodebuild test -scheme CaptionFlow -destination 'platform=macOS' -only-testing:CaptionFlowTests/KeychainStoreTests`

- [ ] **Step 3: Implement Keychain access and Settings form**

Use `kSecClassGenericPassword`, service injection, and `kSecAttrAccessibleAfterFirstUnlock`. Persist only base URL, model, and instruction in `UserDefaults`; bind the key field to Keychain on Save.

- [ ] **Step 4: Add endpoint validation tests**

Test that `https://api.example.com/v1` is accepted and `ftp://example.com` and an empty model are rejected before a session starts.

- [ ] **Step 5: Run tests and commit**

Run: `xcodebuild test -scheme CaptionFlow -destination 'platform=macOS' -only-testing:CaptionFlowTests/KeychainStoreTests`

Commit: `git add CaptionFlow CaptionFlowTests && git commit -m "feat: add secure LLM settings"`

### Task 3: Prove the local ASR dependency and model-download path

**Files:**
- Create: `CaptionFlow/ASR/EnglishASR.swift`, `CaptionFlow/ASR/WhisperASR.swift`, `CaptionFlow/ASR/ModelDownloadService.swift`, `CaptionFlowTests/EnglishASRTests.swift`
- Modify: `CaptionFlow.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces `protocol EnglishASR { func transcribe(samples: [Float]) async throws -> String }` and `ModelDownloadService.downloadRecommendedModel() async throws -> URL`.

- [ ] **Step 1: Add a failing fake-ASR contract test**

```swift
func testASRResultIsTrimmedEnglishText() async throws {
    let asr = FakeASR(result: "  hello world  ")
    XCTAssertEqual(try await asr.transcribe(samples: [0]), "hello world")
}
```

- [ ] **Step 2: Add the maintained `whisper.cpp` Swift Package and pin an exact release**

Use the upstream `ggml-org/whisper.cpp` package; record the chosen tag and model checksum in `ModelCatalog`. Build it for arm64 before continuing. If package integration fails, stop this task and record the compiler failure rather than creating ad-hoc C++ bindings.

- [ ] **Step 3: Implement the ASR adapter behind `EnglishASR`**

Normalize PCM to the package-required mono sample rate, use the downloaded English model, force English language recognition, trim whitespace, and return no result for empty recognized text.

- [ ] **Step 4: Implement resumable model download with integrity validation**

Download to `Application Support/CaptionFlow/Models/<filename>.partial`, validate the expected SHA-256, then atomically rename it to the final model file. Delete only the `.partial` path on failure.

- [ ] **Step 5: Run ASR unit tests and manual Apple-Silicon smoke test; commit**

Run: `xcodebuild test -scheme CaptionFlow -destination 'platform=macOS' -only-testing:CaptionFlowTests/EnglishASRTests`

Manual: transcribe a bundled non-sensitive English fixture and record latency/memory in the PR notes.

Commit: `git add CaptionFlow CaptionFlowTests CaptionFlow.xcodeproj && git commit -m "feat: add local English ASR"`

### Task 4: Add microphone capture and permission isolation

**Files:**
- Create: `CaptionFlow/Capture/AudioCapture.swift`, `CaptionFlow/Capture/MicrophoneCapture.swift`, `CaptionFlowIntegrationTests/CapturePermissionTests.swift`

**Interfaces:**
- Produces `protocol AudioCapture { func requestPermission() async -> Bool; func start(onPCM: @escaping ([Float]) -> Void) throws; func stop() }`.

- [ ] **Step 1: Write a state test for denied microphone permission**

Assert a session transitions from `.requestingPermission` to `.failed("Microphone permission is required")` and never calls `start` when the injected capture returns `false`.

- [ ] **Step 2: Run the test and confirm it fails**

Run: `xcodebuild test -scheme CaptionFlow -destination 'platform=macOS' -only-testing:CaptionFlowIntegrationTests/CapturePermissionTests`

- [ ] **Step 3: Implement AVAudioEngine microphone capture**

Request `AVCaptureDevice.requestAccess(for: .audio)`, install one input-node tap, convert samples to mono `Float`, and invoke `onPCM`. Do not create `AVAudioFile`, `AVAudioRecorder`, or any raw-audio URL.

- [ ] **Step 4: Add a start/stop integration check**

On a developer Mac, grant microphone permission, start capture for five seconds, assert the callback receives at least one non-empty buffer, then stop.

- [ ] **Step 5: Run tests and commit**

Run: `xcodebuild test -scheme CaptionFlow -destination 'platform=macOS'`

Commit: `git add CaptionFlow CaptionFlowIntegrationTests && git commit -m "feat: capture microphone audio"`

### Task 5: Add all-system-audio capture without video persistence

**Files:**
- Create: `CaptionFlow/Capture/SystemAudioCapture.swift`
- Modify: `CaptionFlow/Capture/AudioCapture.swift`, `CaptionFlowIntegrationTests/CapturePermissionTests.swift`

**Interfaces:**
- Produces `SystemAudioCapture: AudioCapture` using `SCStream` audio output only.

- [ ] **Step 1: Write a failing configuration test**

Assert `SystemAudioCapture.makeConfiguration()` sets `capturesAudio == true`, `excludesCurrentProcessAudio == true`, and does not register a screen/video output handler.

- [ ] **Step 2: Run the test and confirm it fails**

Run: `xcodebuild test -scheme CaptionFlow -destination 'platform=macOS' -only-testing:CaptionFlowIntegrationTests/CapturePermissionTests`

- [ ] **Step 3: Implement ScreenCaptureKit audio capture**

Use `SCShareableContent` to build an all-displays filter, configure audio capture, add only `.audio` output, convert `CMSampleBuffer` PCM to `[Float]`, and surface Screen Recording denial as an actionable failure.

- [ ] **Step 4: Manually verify with browser audio**

Play an English public-domain clip, start System Audio, confirm callback buffers arrive, confirm app sounds do not loop back, and inspect Application Support to confirm no audio file exists.

- [ ] **Step 5: Run tests and commit**

Run: `xcodebuild test -scheme CaptionFlow -destination 'platform=macOS'`

Commit: `git add CaptionFlow CaptionFlowIntegrationTests && git commit -m "feat: capture system audio"`

### Task 6: Implement compatible LLM translation and error classification

**Files:**
- Create: `CaptionFlow/Translation/TranslationClient.swift`, `CaptionFlow/Translation/OpenAICompatibleClient.swift`, `CaptionFlowIntegrationTests/TranslationClientTests.swift`

**Interfaces:**
- Produces `protocol TranslationClient { func translate(english: String, instruction: String) async throws -> String }` and `TranslationError.invalidConfiguration`, `.unauthorized`, `.rateLimited`, `.network`, `.invalidResponse`.

- [ ] **Step 1: Write URLProtocol-backed tests for request privacy and response parsing**

Assert the request body contains `english` and `instruction`, contains no audio field, uses the configured `/chat/completions` URL, and extracts `choices[0].message.content`.

- [ ] **Step 2: Run translation-client tests and confirm they fail**

Run: `xcodebuild test -scheme CaptionFlow -destination 'platform=macOS' -only-testing:CaptionFlowIntegrationTests/TranslationClientTests`

- [ ] **Step 3: Implement the client using URLSession**

Send a non-streaming OpenAI-compatible chat-completions request with low temperature and a system instruction forbidding commentary. Map HTTP 401/403 to `.unauthorized`, 429 to `.rateLimited`, and transport errors to `.network`.

- [ ] **Step 4: Add a failing malformed-response test, then implement `.invalidResponse`**

Use a `200` response with no message content; the UI must never show an empty Chinese line as success.

- [ ] **Step 5: Run tests and commit**

Run: `xcodebuild test -scheme CaptionFlow -destination 'platform=macOS' -only-testing:CaptionFlowIntegrationTests/TranslationClientTests`

Commit: `git add CaptionFlow CaptionFlowIntegrationTests && git commit -m "feat: add compatible LLM translation"`

### Task 7: Coordinate provisional caption updates and committed history

**Files:**
- Create: `CaptionFlow/Translation/TranslationCoordinator.swift`, `CaptionFlow/Presentation/SessionViewModel.swift`, `CaptionFlowTests/TranslationCoordinatorTests.swift`, `CaptionFlowTests/SessionViewModelTests.swift`

**Interfaces:**
- Consumes: `EnglishASR`, `TranslationClient`, `AudioCapture`.
- Produces `@MainActor final class SessionViewModel` with `var captions: [Caption]`, `var provisionalCaption: Caption?`, `func start() async`, and `func stop()`.

- [ ] **Step 1: Write a failing coalescing test**

Feed `"hello"`, then `"hello world"` before the debounce interval and assert the client translates only `"hello world"` and the original provisional UUID remains unchanged.

- [ ] **Step 2: Run the coordinator test and confirm it fails**

Run: `xcodebuild test -scheme CaptionFlow -destination 'platform=macOS' -only-testing:CaptionFlowTests/TranslationCoordinatorTests`

- [ ] **Step 3: Implement 350 ms debounce and cancellation**

Cancel an in-flight translation when superseded; emit only the latest provisional result. Commit a caption when ASR supplies a finalized segment or the session stops.

- [ ] **Step 4: Add failure continuity test**

Make `TranslationClient` throw `.rateLimited`; assert the English provisional caption remains visible, Chinese is nil, and the view model exposes `"Translation temporarily unavailable"` while capture state stays `.running`.

- [ ] **Step 5: Run tests and commit**

Run: `xcodebuild test -scheme CaptionFlow -destination 'platform=macOS' -only-testing:CaptionFlowTests`

Commit: `git add CaptionFlow CaptionFlowTests && git commit -m "feat: coordinate live captions"`

### Task 8: Build the main window and floating subtitle panel

**Files:**
- Create: `CaptionFlow/Presentation/MainWindowView.swift`, `CaptionFlow/Presentation/FloatingCaptionPanel.swift`
- Modify: `CaptionFlow/CaptionFlowApp.swift`, `CaptionFlow/Presentation/SessionViewModel.swift`

**Interfaces:**
- Consumes: `SessionViewModel`.
- Produces a floating `NSPanel` controlled by `FloatingCaptionPanel.show(viewModel:)` and `hide()`.

- [ ] **Step 1: Write view-model tests for source selection and Start enablement**

Assert Start is disabled without a saved configuration or model, enabled when both exist, and source selection is exactly `.microphone` or `.systemAudio`.

- [ ] **Step 2: Run tests and confirm they fail**

Run: `xcodebuild test -scheme CaptionFlow -destination 'platform=macOS' -only-testing:CaptionFlowTests/SessionViewModelTests`

- [ ] **Step 3: Implement the main controls and panel**

Expose Start/Stop, source picker, status text, Settings, and History. Render latest English and Chinese lines in a borderless floating panel with a pin control, drag region, opacity slider, font-size control, and Chinese-only toggle.

- [ ] **Step 4: Perform manual visual acceptance**

During a capture session, move the panel over a browser, pin it above other windows, change font size/opacity, toggle Chinese-only, and confirm it does not steal focus while captions update.

- [ ] **Step 5: Run tests and commit**

Run: `xcodebuild test -scheme CaptionFlow -destination 'platform=macOS'`

Commit: `git add CaptionFlow CaptionFlowTests && git commit -m "feat: add live subtitle interface"`

### Task 9: Persist local history and export text

**Files:**
- Create: `CaptionFlow/Persistence/SessionStore.swift`, `CaptionFlow/Presentation/HistoryView.swift`, `CaptionFlowTests/SessionStoreTests.swift`

**Interfaces:**
- Produces `SessionStore.save(captions:)`, `loadSessions()`, `delete(sessionID:)`, and `exportText(sessionID:) throws -> URL`.

- [ ] **Step 1: Write a failing persistence and export test**

Save captions containing one English/Chinese pair, reload them from a temporary directory, export, and assert the UTF-8 text includes both strings but neither an API key nor an audio path.

- [ ] **Step 2: Run the persistence test and confirm it fails**

Run: `xcodebuild test -scheme CaptionFlow -destination 'platform=macOS' -only-testing:CaptionFlowTests/SessionStoreTests`

- [ ] **Step 3: Implement JSON history and `.txt` exporter**

Save sessions under `Application Support/CaptionFlow/Sessions/<UUID>.json`; export timestamps, English, and Chinese to a user-selected URL via NSSavePanel. Do not create `.srt` or audio artifacts.

- [ ] **Step 4: Add deletion test**

After `delete(sessionID:)`, assert its JSON no longer exists and it is absent from `loadSessions()`.

- [ ] **Step 5: Run tests and commit**

Run: `xcodebuild test -scheme CaptionFlow -destination 'platform=macOS' -only-testing:CaptionFlowTests/SessionStoreTests`

Commit: `git add CaptionFlow CaptionFlowTests && git commit -m "feat: save and export caption history"`

### Task 10: End-to-end privacy, latency, and beta-readiness validation

**Files:**
- Create: `docs/beta-test-script.md`, `CaptionFlowIntegrationTests/EndToEndSessionTests.swift`
- Modify: `CaptionFlow/CaptionFlowApp.swift`

**Interfaces:**
- Consumes the complete app and the acceptance criteria in `docs/specs/2026-09-22-macos-live-translation-mvp.md`.

- [ ] **Step 1: Write an end-to-end fixture test**

Inject a fake PCM source, deterministic ASR, and URLProtocol translation response. Assert English then Chinese reaches `SessionViewModel`, stopping commits history, and no fixture produces an audio file in the temporary persistence directory.

- [ ] **Step 2: Run the test and confirm it fails before wiring**

Run: `xcodebuild test -scheme CaptionFlow -destination 'platform=macOS' -only-testing:CaptionFlowIntegrationTests/EndToEndSessionTests`

- [ ] **Step 3: Wire dependencies through `CaptionFlowApp`**

Create production implementations only in the composition root; inject fakes in tests. Configure the app privacy usage description for microphone and ensure no logs include URL query secrets, Authorization headers, or transcript content by default.

- [ ] **Step 4: Execute the beta test script**

The script must cover first-run model download, both permission paths, invalid key, offline network, rate limit, deleting history, `.txt` export, no-audio-file inspection, browser system-audio test, microphone test, and measured subtitle latency.

- [ ] **Step 5: Archive, sign, notarize, and commit release documentation**

Run all tests, create an Archive in Xcode using Developer ID signing, notarize the `.dmg`, and install it on a clean Apple Silicon test account. Record exact build/version and test outcomes in the beta notes.

Commit: `git add CaptionFlow CaptionFlowTests CaptionFlowIntegrationTests docs && git commit -m "chore: prepare closed beta"`

## Self-review

- Spec coverage: Tasks 1–2 cover platform/configuration/security; 3–5 cover local ASR and both input sources; 6–7 cover compatible LLM incremental translation and failure continuity; 8–9 cover subtitle UX/history/export; 10 covers privacy, latency, distribution, and beta acceptance.
- Non-goals remain absent: no individual-app picker, audio persistence, non-English languages, accounts, billing, summaries, or browser extension.
- Placeholder scan: no task depends on unspecified implementation behavior; model release and checksum are deliberately selected and recorded during the bounded integration spike before application code assumes them.
- Interface consistency: `AudioCapture`, `EnglishASR`, `TranslationClient`, `Caption`, and `SessionViewModel` names/signatures are declared before their consumers.
