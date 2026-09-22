# CaptionFlow: Settings Redesign & Transcrybe-Inspired Feature Roadmap

## Background

The user asked CaptionFlow to reference the third-party app Transcrybe's feature set
(menu-bar dropdown, multi-pane Settings window) and plan which pieces to build. Current
state: CaptionFlow is a single window app; Settings is one `Form` with a single "LLM"
section (API style/base URL/model/instruction/API key). No menu-bar mode, no global
hotkeys, hardcoded English→Simplified Chinese language pair, no history persistence, no
subtitle appearance/opacity controls, no custom vocabulary.

Not building: account/purchase/license/trial (CaptionFlow has no paid tier).

## Roadmap (4 phases, in dependency order)

1. **Settings window redesign (infrastructure)** — sidebar + content layout with
   placeholder sections for 启动/文本外观/显示设置/翻译设置/快捷键/自定义词汇/关于; move
   the existing LLM form into 翻译设置; add a selectable target language.
2. **Subtitle window display** — 文本外观 (font/size/color), 显示设置 (window opacity,
   pin/move-to-screen).
3. **Audio source & hotkeys** — per-app audio source filtering (menu bar "音频源"
   submenu), global hotkeys (toggle captions, move to screen, switch source).
4. **Menu bar mode + history** — convert the app shell to `MenuBarExtra`, add persisted
   session history, add custom vocabulary (word list fed into the ASR/translation
   prompt).

## Phase 1 detailed design (this iteration)

### Scope decision: source language stays fixed

Speaking language stays hardcoded to English for this iteration. WhisperKit currently
loads `base.en` (an English-only model) and the whole ASR protocol is named
`EnglishASR`. Making the *speaking* language selectable would require switching to a
multilingual WhisperKit model variant and reworking `EnglishASR`'s contract — a
materially bigger change than this iteration's scope. Only the **target** (translation)
language becomes selectable.

### Settings window: sidebar layout

Replace the single `Form` in `SettingsView` with a `NavigationSplitView`: a sidebar list
of sections, and a detail pane per section.

- 启动, 文本外观, 显示设置, 快捷键, 自定义词汇, 关于 — placeholder panes ("即将推出") for
  now; each becomes a real pane in a later phase.
- 翻译设置 — the only functional pane this iteration. Contains the existing LLM form
  fields (API style, base URL, model, instruction, API key) plus a new **目标语言**
  picker.

### Target language

New `TargetLanguage` enum (`CaptionFlow/Translation/TargetLanguage.swift`): a curated,
fixed list of `(code, displayName)` pairs covering languages Apple's on-device
Translation framework and mainstream LLMs both handle well — Simplified Chinese,
Traditional Chinese, Japanese, Korean, Spanish, French, German, Russian, Portuguese,
Arabic. Persisted via `@AppStorage("translation.targetLanguage")`, default
`zh-Hans`.

Wiring:

- `TranslationSessionHolder` (in `AppleTranslator.swift`) gains
  `updateTarget(_ language: Locale.Language)`, which replaces `configuration` with a new
  `TranslationSession.Configuration` (source stays `en`). Reassigning triggers SwiftUI's
  `.translationTask` to re-negotiate a session for the new target.
- `LLMTranslator` gains a `targetLanguageName: String` parameter, appended to the
  outgoing prompt as an explicit target-language directive (independent of whatever the
  user's free-text "instruction" field says), so the picker works regardless of how the
  user has customized the instruction text.
- `CaptionSessionController.makeTranslator()` reads the stored target-language code,
  resolves it to a `TargetLanguage`, calls `translationSessionHolder.updateTarget(...)`,
  and passes `targetLanguage.displayName` into `LLMTranslator`.

### Explicitly out of scope for Phase 1

- Speaking-language selection (see above).
- Any of the placeholder sections' actual functionality.
- Per-app audio source filtering, hotkeys, menu bar mode, history, custom vocabulary —
  all later phases.
