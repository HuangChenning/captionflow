# CaptionFlow code-completion workflow

## Trigger

A user asks to complete outstanding CaptionFlow MVP work without requesting device validation or release distribution.

## Outcome

The app builds and automated tests pass with all code-complete MVP behavior: persistent LLM profiles, local caption history and UTF-8 export, LLM refinement with an approved glossary, and local translation resource readiness.

## Scope

Include code and automated tests only. Exclude microphone/system-audio hardware tests, real-provider calls, signing, notarization, and beta distribution.

## Workflow

1. Inspect the current branch, tests, implementation plan, and TODO document. Reconcile documentation with implemented code before changing behavior.
2. Keep secrets in Keychain. Save non-secret LLM profiles as JSON in Application Support and migrate legacy UserDefaults profiles once.
3. Save completed caption sessions locally as JSON. Provide a history UI that lists, deletes, and exports UTF-8 text containing timestamps, English, and Chinese only.
4. Produce the local translation first. Send the English source, local draft, user instruction, and only user-confirmed glossary entries to the LLM refiner. Keep the local result visible whenever refinement fails or is delayed.
5. Show LLM-originated terminology as reviewable candidates. A candidate may be edited, accepted, or discarded; only acceptance persists it to the local glossary for future requests.
6. On launch and before local-only/auto translation, check English-to-Simplified-Chinese availability with `LanguageAvailability.status(from:to:)`. Show installed, downloadable, and unsupported states distinctly.
7. For a downloadable pairing, expose an explicit install action that uses `TranslationSession.prepareTranslation()`. Recheck after the operation. If installation fails or remains unavailable, allow English captions and show an actionable local-translation error.
8. Add tests before every new domain behavior. Run the complete suite with code signing disabled when the host signing service is unavailable.
9. Update TODO and plan documentation with completed work and manual acceptance work left for a later loop.

## Checkpoint

One final human checkpoint after all automated tests pass. The brief must state the changed behavior, test result, remaining manual validation, and links to the relevant implementation and TODO files.

## Non-negotiable constraints

- Never persist raw audio or video.
- Never send API keys or audio to an LLM endpoint.
- Never automatically promote an LLM-generated term into the glossary.
- Never claim local translation is ready when the language pairing is not installed.
