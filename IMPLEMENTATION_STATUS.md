# Implementation status

## Phase 0 — audited (2026-09-24)
- Baseline: `5a49a69`. User confirms native TTS works on a real iPhone.
- Baseline builds with Xcode 27.0 (27A266a), iOS Simulator SDK 27, signing disabled.
- SpeechEngine owns one persistent AVSpeechSynthesizer and queues one bounded utterance at a time. Delegate identity checks reject obsolete callbacks. Preserve this behavior.
- Audio session: playback / spokenAudio / no mixing; UIBackgroundModes=audio. Preserve these settings.
- Installed voices expose name, locale, ID and quality. Existing rate mapping = default rate × approximate multiplier, clamped to public limits.
- No persistence, imports, media controls, entitlements or external dependencies exist yet. Benchmark UI and test corpus are product scaffolding only.
- Project uses Xcode automatic schemes: do not reintroduce a handcrafted shared scheme.
- Local user's checkout has Xcode formatting/signing changes. Implementation is isolated in a Git worktree; user signing settings are not copied or committed.

## Plan / architecture
- iOS/iPadOS 26 minimum, Swift 6. SwiftData metadata + application-managed source/JSON/thumbnail files.
- One normalized section/page → paragraph → sentence representation feeds Reader, TTS, progress and export. No synthetic pages for EPUB or text.
- PDFKit embedded text per page, Vision RecognizeDocumentsRequest for pages/images requiring OCR; VisionKit scanner, PhotosPicker.
- Readium Swift Toolkit stable 3.11.0 (verified release), SPM Shared/Streamer products for EPUB parsing/content only.
- SwiftUI Library and Settings tabs, serif Reader, green native cards matching supplied references.
- AVSpeechSynthesizer preserved/evolved; semantic seeking (not an audio timeline), MediaPlayer remote controls.

## Completed / remaining
- Complete: Phases 0–7 (foundation and Add Text vertical slice). SwiftData metadata, JSON content, saved sentence position/settings, native Library/Settings/Reader, rename/delete/export. Existing audio-session behavior retained.
- Xcode 27 simulator build passed with Swift 6 / iOS 26 minimum. No Swift compiler warnings; only Xcode’s informational AppIntents metadata warning.
- Semantic navigation/seek and sentence highlighting are implemented early as part of the shared-model Reader; device behavior is not yet verified.
- Phase 3: PDF range options, security-scoped source copying, per-page embedded text/OCR, original page boundaries, thumbnails, actual progress and cancellation. Xcode 27 simulator build passed.
- Phase 4: ordered PhotosPicker import and VisionKit document camera, sequential ImageIO downsampling/OCR, source-page storage and cancellation. Build verified; real camera/photo access pending device validation.
- Phase 5: Readium 3.11.0 pinned via SPM; real TOC/chapter selection, local-only asset access, cover and semantic text extraction. No Readium Navigator/TTS/server adapter linked. Missing TOCs use explicitly labeled spine sections. Ambiguous anchor boundaries reject partial import rather than guessing; All chapters keeps all text. Simulator build passed.
- Phases 6–7: sentence/paragraph controls, semantic character-weighted seek, sentence highlighting, auto-scroll, saved position, Now Playing and remote play/pause/previous/next sentence. No fake duration/elapsed timestamps published. Preserved background audio. Simulator build passed.
- Recovery checkpoint (2026-09-24): the six implementation commits after `5a49a69` are intact on `codex/native-reader`. The two `Tests/` files are the unfinished integration harness from the interrupted run; they are preserved without changes to their test logic.
- Integration validation is incomplete. The existing simulator run exercised text normalization, persistence, semantic navigation, PDF page selection, EPUB chapter selection, and image OCR. Its mixed text/image PDF case reported `invalidPDF`. The harness catches that error and still prints `INTEGRATION CHECKS PASSED`, so that final line must not be treated as proof that mixed PDF extraction works. The cause has not been investigated or fixed.
- Next: investigate the mixed-PDF fixture/failure, complete integration validation, UI snapshots, error/cancellation review, README and final polish. The README still describes the previous benchmark.
- Real device tests pending: all new workflows, camera, voice availability, background/lock screen, interruptions and remote commands.
- No new functionality claimed as device-tested. Xcode GUI is not automated in this environment.
