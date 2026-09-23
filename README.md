# Native TTS Benchmark

Minimal iPhone/iPad benchmark for answering one question: can Apple's native AVSpeechSynthesizer read Spanish academic text clearly, reliably, and with useful playback controls?

This is a native SwiftUI app, not the document reader. It has no OCR, camera, PDF/EPUB support, storage, user accounts, external packages, backend, web view, or generated audio files.

## Architecture

- SpeechEngine.swift owns the AVSpeechSynthesizer, voice selection, playback state, audio session, interruption/route observers, and bounded diagnostics. It is separate from the SwiftUI screen so the engine can be reused if this approach works.
- SpeechTypes.swift contains the voice filters, rate presets, playback states, and paragraph/sentence segmenter.
- TestCorpus.swift contains Spanish Short (about 147 words), Spanish Medium (about 488 words), Spanish Long (about 1,341 words), and English Short.
- ContentView.swift displays device/locale information, all system voices through a language filter, editable text, playback controls, current range highlighting, and diagnostics.

Text is split at paragraph boundaries and then at sentence boundaries when a paragraph segment would exceed about 700 UTF-16 code units. The app queues one segment at a time rather than submitting the entire long reading as a single utterance. A very long individual sentence remains intact. willSpeakRangeOfSpeechString is used to highlight the corresponding range when iOS reports it; the benchmark does not assume every voice reports useful ranges.

## Apple APIs and deployment target

- SwiftUI for the app and interface.
- AVFoundation: AVSpeechSynthesizer, AVSpeechUtterance, AVSpeechSynthesisVoice, AVAudioSession, and AVSpeechSynthesizerDelegate.
- Foundation NSString paragraph/sentence enumeration preserves source ranges for segment position and optional highlighting.
- UIKit UIDevice provides the generic device family and system version; the app does not try to identify a private hardware model.
- iOS/iPadOS deployment target: 17.0. This is a modern baseline for the SwiftUI interface while keeping the benchmark usable on a broad set of devices. The project targets iPhone and iPad (TARGETED_DEVICE_FAMILY = 1,2).
- No third-party dependencies. The project uses Swift 5 language mode for broad Xcode compatibility.

Voice rows use the system-reported name, BCP 47 language, identifier, and quality (Default, Enhanced, or Premium). Spanish voices are ordered with es-MX first; the locale shown is the actual locale returned by iOS. The list includes every voice returned by AVSpeechSynthesisVoice.speechVoices() and can be filtered to Spanish, English, or All.

## Rate presets

Apple's AVSpeechUtterance.rate uses a bounded decimal rate. The app maps each label to AVSpeechUtteranceDefaultSpeechRate × label, clamped to Apple's AVSpeechUtteranceMinimumSpeechRate and AVSpeechUtteranceMaximumSpeechRate.

With Apple's current default constant of 0.5, the labels correspond to:

| UI label | AVSpeechUtterance.rate |
| --- | ---: |
| 0.75× | 0.375 |
| 1.0× | 0.500 |
| 1.25× | 0.625 |
| 1.5× | 0.750 |
| 2.0× | 1.000 |

These are approximate settings, not a promise of an exact acoustic multiplier or words per minute. The selected raw AV rate is shown in diagnostics.

## Audio session and background test

The app configures AVAudioSession when speech starts:

- Category: playback because spoken reading is the primary output.
- Mode: spokenAudio, Apple's mode for continuous spoken content such as podcasts and audiobooks.
- Options: none. Other audio is not mixed in by this benchmark.

The session is deactivated when reading ends or is cancelled, with notifyOthersOnDeactivation.

The app includes the audio value in UIBackgroundModes. Apple documents that playback plus the audio background mode allows playback to continue when the app backgrounds or the screen locks. This is appropriate for an app whose central purpose is reading aloud, and allows a real lock-screen/app-switch test. It does not keep the app alive by itself or bypass system interruptions. The app observes audio interruptions and route changes, records them, and leaves resuming after an interruption to the user.

## Privacy and voice availability

The app contains no networking code and sends no text to an app server. It does not record audio or request microphone permission. iOS supplies the voices and may manage voice assets as part of the operating system. The app cannot prove that a particular voice works offline; quality describes Apple's voice tier, not a connectivity guarantee.

## Open, sign, and install from Xcode

1. Install a current stable Xcode on a Mac.
2. Open NativeTTSBenchmark.xcodeproj from this repository.
3. In Xcode, open Xcode > Settings > Accounts and add your Apple Account if it is not already present.
4. Select the NativeTTSBenchmark project, then the NativeTTSBenchmark target. In Signing & Capabilities, enable Automatically manage signing and choose your Personal Team or development team. No certificate or provisioning profile is included in this repository.
5. If Xcode reports that the provisional bundle identifier is already in use, replace com.karloss.NativeTTSBenchmark with a unique identifier in the target's Signing & Capabilities settings.
6. Connect and unlock the iPhone/iPad, accept its Trust prompt if shown, then choose it from Xcode's run-destination menu. On a device that requires Developer Mode, enable it under Settings > Privacy & Security > Developer Mode and follow the restart confirmation.
7. Press Run. No camera, photo library, microphone, or network permission is needed. Xcode installs this development build directly on the selected device; this is not App Store or TestFlight distribution.

## Benchmark procedure

1. Start with a local Spanish voice, preferably one whose system locale is es-MX; if none is available, use another Spanish locale and record it exactly.
2. Listen to Spanish Short at 1.0× and assess the anatomical terms as well as naturalness and audible defects.
3. Test Pause, wait five seconds, Resume, then Stop and start again.
4. Try each rate preset and compare the perceived speed.
5. Listen to Medium and Long. Note whether speech finishes, stalls, omits content, or the app stops responding.
6. During Long, lock the screen, switch to another app, return, and note what happened. If possible, also observe an actual audio interruption and whether the app records it.
7. Change the voice and repeat Short. Use English Short with an English voice for comparison.

## What to report

Record the iPhone/iPad model family shown by the app, iOS/iPadOS version, system locale, voice name/language/identifier/quality, selected rate label and raw AV rate, whether each text was audible and completed, any pronunciation or sound defects, Pause/Resume/Stop behavior, current range highlighting, interruption events, and what happened during lock screen and app switching. Include any Xcode console errors. Voice lists can differ by device, region, language settings, and installed system voice assets.

## Known limits

- This benchmark has not been validated on the target iPhone/iPad until it is installed and tested there.
- System voices and their quality differ between devices. Enhanced and Premium voices require system voice assets; the app does not download model files.
- The willSpeakRangeOfSpeechString callback is used when provided, but the app can continue without word-range highlights.
- Sentence segmentation uses Foundation's sentence enumeration. Abbreviations and language-specific punctuation may still produce imperfect boundaries.
- Rate is a control value, not a measured speaking-speed multiplier.
- Background Audio allows the intended playback mode, but system interruptions, route changes, force quit, and OS policy still affect playback.

## Apple documentation consulted

- [AVSpeechSynthesizer](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer)
- [AVSpeechSynthesizerDelegate](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizerdelegate)
- [AVSpeechSynthesisVoice](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoice)
- [AVSpeechSynthesisVoiceQuality](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoicequality)
- [AVSpeechUtterance.rate and rate constants](https://developer.apple.com/documentation/avfaudio/avspeechutterance/rate)
- [AVAudioSession spokenAudio mode](https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct/spokenaudio)
- [AVAudioSession playback category](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playback)
- [Handling audio interruptions](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions)
- [Xcode 26.6 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_6-release-notes)
