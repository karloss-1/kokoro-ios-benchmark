# Document Reader — iOS / iPadOS

A native, local document library for reading and listening with Apple's system voices. The existing `NativeTTSBenchmark.xcodeproj` name and provisional bundle identifier remain so the project can evolve from the original benchmark without replacing its history.

## Requirements and installation

- iPhone or iPad running **iOS/iPadOS 26.0 or later**. Swift 6; current builds use Xcode 27 and its Simulator SDK. No compatibility layer for earlier systems.
- Open `NativeTTSBenchmark.xcodeproj`. Xcode automatically manages the application scheme; no handcrafted shared scheme is required.
- Allow Swift Package Manager to resolve the pinned packages (internet is needed for this development step).
- Select the **NativeTTSBenchmark** target → **Signing & Capabilities** → your Apple development team. No team, keys or provisioning profiles are committed. Change `com.karloss.NativeTTSBenchmark` if your account needs a unique identifier.
- Connect and unlock the iPhone/iPad, trust the Mac, enable **Settings → Privacy & Security → Developer Mode** when prompted, select the device in Xcode and press Run.
- Camera access is requested only for Scan pages. PhotosPicker grants access to selected images; the app does not request unrestricted photo-library or microphone access.

## Use

Library is the home screen. The green **+** opens Scan pages, Choose photos, Import PDF, Import EPUB or Add text. PDF imports support all pages or an inclusive page range. EPUB imports expose the real table of contents and allow noncontiguous chapter selection. A missing table of contents is explicitly represented by reading-order sections.

The library supports search, sorting, Continue Listening, rename, deletion and Export Text. Reader presents the processed text, sentence highlighting, optional auto-scroll and navigation by sentence, paragraph or section/page. Tap a sentence to read from it. The slider selects a sentence by its proportional character position; it is not an audio-file timeline. Position survives app relaunch and voice/rate changes. Settings holds voice, speaking rate, highlighting, auto-scroll and System / Light / Dark appearance; Reader also offers text size and speaking rate.

**Export Text** writes the same normalized paragraphs used by Reader/TTS, with page markers for PDF/photos/scans and chapter headings where present. OCR spelling is not silently corrected. Export contains only imported pages/sections. No WAV/MP3 is generated.

## Architecture

`Source → ReadingDocument → Reader + SpeechEngine + Export Text`

- `DocumentModel`: normalized sections/pages, paragraphs and sentences, segmented with NaturalLanguage. SwiftData stores library metadata and semantic reading position.
- `LibraryStorage`: originals, normalized JSON and thumbnails under Application Support, independent of the source file's original location. Files are written atomically; source processing happens before the library entry is added.
- `ImportCoordinator`: cancellable import lifecycle, actual page/resource progress and cleanup. Extraction and filesystem work run in actors.
- `DocumentExtractor`: PDFKit uses embedded text per page. Pages without a usable text layer and imported images use **Vision RecognizeDocumentsRequest**, available from iOS 26. ImageIO downsamples and applies EXIF orientation. VisionKit provides the document scanner.
- `EPUBService`: **Readium Swift Toolkit 3.11.0**, pinned by `Package.resolved`, using Shared/Streamer only. Its Content iterator extracts local EPUB text; no Readium Navigator, TTS or HTTP server is used. Readium still labels this Content API experimental; ambiguous chapter anchors reject partial selection with a visible explanation instead of guessing.
- `SpeechEngine`: one persistent AVSpeechSynthesizer and one sentence at a time. Utterance identity checks ignore callbacks from speech cancelled by navigation. Completion is stored separately from the playback state.
- `SystemMedia`: Now Playing metadata and remote play/pause/stop/previous/next sentence. It publishes no fabricated duration or elapsed audio timestamps.

The only direct external package is Readium 3.11.0. Its resolved dependencies are recorded in `Package.resolved`; Xcode links only dependencies required by Shared/Streamer. There are no web app, Kokoro, Transformers or ONNX components.

## Speech, progress and background audio

Voices are the system's actual `AVSpeechSynthesisVoice` list; Spanish is prioritized, with `es-MX` first. Automatic selection follows the detected document language. Available voices and quality tiers vary by device and installed voice assets.

Labels 0.75×–2× map to `AVSpeechUtteranceDefaultSpeechRate × multiplier`, clamped to Apple's public minimum/maximum. At the current default of 0.5, 1× is 0.5 and 1.5× is 0.75. These labels are approximate controls, not measured acoustic speed. Changing rate/voice during speech restarts the current sentence.

Progress is the current sentence's character offset divided by the document's total sentence characters; completion is 100%. It remains meaningful when rate changes. The app does not estimate remaining minutes from unmeasured speech duration.

AVAudioSession uses **`.playback` / `.spokenAudio` / no mixing options**. The legitimate `audio` background mode permits spoken reading while locked or in another app. Audio interruptions and disconnected output devices pause reading; resume is manual. System policy, force quit and audio interruptions can still stop playback. Physical-device checks are required for lock-screen and Control Center behavior.

## Privacy, offline use and limits

There is no application backend, CloudKit synchronization, account, subscription, analytics or synthesis API. EPUB's HTTP client explicitly refuses network requests. The app never sends document text to an application server.

Core extraction and speech use local files and Apple frameworks. Files/Photos may need to download an iCloud item before granting it to the app; make documents and desired system voices available before testing in airplane mode. Apple's voice asset management does not provide an absolute per-voice offline guarantee to this app.

- DRM/protected EPUBs and locked or copy-restricted PDFs are rejected. Damaged/unsupported inputs show an error.
- Embedded PDF text order depends on the source PDF. Mixed-layout pages with a usable text layer use that layer; OCR is selected per page, not per illustration. Multi-column layouts, handwriting, tables and OCR language accuracy need review on representative documents.
- Cancellation is checked between stages/pages and after Vision returns; the current system operation may finish first. No partial document is added after cancellation.
- Large documents retain normalized text in memory, while image rendering/OCR is sequential. Real-device memory/performance testing remains necessary.
- Imported metadata/positions are local. Deleting the app deletes its library. There is no document synchronization or Share Extension in this version.

## Validation

See **IMPLEMENTATION_STATUS.md** for the current build, passing checks, known failures and device-only work. Simulator results do not establish iPhone/iPad audio or memory behavior.

The Simulator implementation/QA phase is closed for physical-device evaluation (2026-09-25). Final clean build passed in Xcode 27; essential smoke coverage reuses the recent passing tests listed in the status file. iPad Files/EPUB automation remains incomplete because of accessibility lookup failures; no production defect was established by that test. No essential-flow blocker is currently known.

Build without signing:

```sh
xcodebuild -project NativeTTSBenchmark.xcodeproj -scheme NativeTTSBenchmark \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/NativeReaderBuild \
  CODE_SIGNING_ALLOWED=NO build
```

With a booted simulator, the core integration harness compiles the real production services and exercises generated PDF/EPUB/image fixtures, persistence and navigation:

```sh
python3 Tests/run-integration.py /tmp/NativeReaderBuild SIMULATOR_UDID
```

UI checks use XCTest in a temporary copy of the project, leaving the application's schemes and targets unchanged. The default is the text/Reader/Settings smoke flow:

```sh
python3 Tests/run-ui.py SIMULATOR_UDID
```

Select another focused flow with `READER_UI_TEST`, for example `READER_UI_TEST=testEPUBSelectAll python3 Tests/run-ui.py SIMULATOR_UDID`. Comma-separated test names are supported. Actual exported-file checks run for the corresponding single selected flow. `testPhotoImport` expects a fresh validation simulator where the two staged images are the newest images; avoid repeating media staging into a personal/long-lived photo library.

At accessibility text sizes, Library uses vertical cards and Reader shows navigation icons with full accessibility labels. Long-press a navigation icon for Apple's enlarged label viewer. Text retains the system's requested size and scrolls.

The optional third argument to the core runner seeds a **simulator-only** app data container for inspection. Never pass a real-device or personal library path. Tests retain fixture artifacts and XCTest results in temporary directories for diagnosis.

## First physical-device pass

1. Install using the instructions above and verify the first Library launch. Select an installed Spanish voice in Settings and set 1×; compare Enhanced voices if exposed by the device. Add a short academic text; verify audible pronunciation, Play/Pause, sentence/paragraph jumps, highlighting, auto-scroll and semantic slider seeking.
2. Leave at a known sentence, relaunch, and confirm the position. Test another voice/rate and Dark/System appearance.
3. Import a digital PDF, a scanned PDF and a mixed PDF. Try a page range; compare the displayed/exported text with the original pages.
4. Select multiple photos in a known order; scan two pages; inspect OCR and page markers. Cancel a longer import and confirm no partial library entry remains.
5. Import an EPUB with selected noncontiguous chapters and one without a TOC. Check chapter boundaries and export.
6. During longer speech, lock/unlock, switch apps, inspect Lock Screen and Control Center / Now Playing, and try their available play/pause/previous/next commands plus headphone remote controls. Disconnect headphones and test an interruption. Record behavior without assuming background success.
7. Repeat local-document reading/OCR/speech in airplane mode and test representative large books.

Report device/OS, voice name/locale/quality, document type and size/page count, exact failing action, whether relaunch restores position, screenshots of extraction/UI issues and relevant Xcode logs.

## Sources

- [Vision document recognition (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/272/)
- [RecognizeDocumentsRequest](https://developer.apple.com/documentation/vision/recognizedocumentsrequest)
- [AVSpeechSynthesizer](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer)
- [Spoken audio mode](https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct/spokenaudio)
- [Readium Swift Toolkit 3.11.0](https://github.com/readium/swift-toolkit/releases/tag/3.11.0)
