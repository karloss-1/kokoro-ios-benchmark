import AVFoundation
import Foundation

enum VoiceFilter: String, CaseIterable, Identifiable {
    case spanish = "Spanish"
    case english = "English"
    case all = "All"

    var id: String { rawValue }
}

enum SpeechRatePreset: Float, CaseIterable, Identifiable {
    case slower = 0.75
    case normal = 1.0
    case quicker = 1.25
    case fast = 1.5
    case double = 2.0

    var id: Float { rawValue }

    var label: String {
        switch self {
        case .slower: "0.75×"
        case .normal: "1.0×"
        case .quicker: "1.25×"
        case .fast: "1.5×"
        case .double: "2.0×"
        }
    }

    /// Approximate multiplier anchored to Apple's default speech rate.
    /// Clamp to the public rate range so every preset remains valid.
    var avSpeechRate: Float {
        min(
            max(AVSpeechUtteranceDefaultSpeechRate * rawValue,
                AVSpeechUtteranceMinimumSpeechRate),
            AVSpeechUtteranceMaximumSpeechRate
        )
    }
}

enum PlaybackState: String {
    case ready
    case speaking
    case paused
    case interrupted
    case stopping
    case finished
    case stopped
    case failed

    var label: String {
        switch self {
        case .ready: "Ready"
        case .speaking: "Speaking"
        case .paused: "Paused"
        case .interrupted: "Interrupted"
        case .stopping: "Stopping"
        case .finished: "Finished"
        case .stopped: "Stopped"
        case .failed: "Error"
        }
    }

    var isActive: Bool {
        switch self {
        case .speaking, .paused, .interrupted, .stopping: true
        case .ready, .finished, .stopped, .failed: false
        }
    }
}

struct SpeechSegment: Identifiable {
    let id: Int
    let paragraph: Int
    let text: String
    let sourceRange: NSRange
}

enum SampleText: String, CaseIterable, Identifiable {
    case spanishShort = "Spanish · Short"
    case spanishMedium = "Spanish · Medium"
    case spanishLong = "Spanish · Long"
    case englishShort = "English · Short"

    var id: String { rawValue }

    var text: String {
        switch self {
        case .spanishShort: TestCorpus.spanishShort
        case .spanishMedium: TestCorpus.spanishMedium
        case .spanishLong: TestCorpus.spanishLong
        case .englishShort: TestCorpus.englishShort
        }
    }
}

enum TextSegmenter {
    /// Keeps utterances manageable while preserving sentence and paragraph
    /// boundaries. A single unusually long sentence remains intact.
    static func segments(in text: String, maximumUTF16Length: Int = 700) -> [SpeechSegment] {
        let source = text as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        var output: [SpeechSegment] = []
        var paragraphNumber = 0

        source.enumerateSubstrings(in: fullRange, options: .byParagraphs) { _, paragraphRange, _, _ in
            let paragraphText = source.substring(with: paragraphRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !paragraphText.isEmpty else { return }

            paragraphNumber += 1
            var sentenceRanges: [NSRange] = []
            source.enumerateSubstrings(in: paragraphRange, options: .bySentences) { sentence, range, _, _ in
                guard let sentence,
                      !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                sentenceRanges.append(range)
            }

            guard !sentenceRanges.isEmpty else {
                output.append(
                    SpeechSegment(
                        id: output.count,
                        paragraph: paragraphNumber,
                        text: source.substring(with: paragraphRange),
                        sourceRange: paragraphRange
                    )
                )
                return
            }

            var groupStart: Int?
            var groupEnd = 0

            func appendGroup() {
                guard let start = groupStart, groupEnd > start else { return }
                let range = NSRange(location: start, length: groupEnd - start)
                output.append(
                    SpeechSegment(
                        id: output.count,
                        paragraph: paragraphNumber,
                        text: source.substring(with: range),
                        sourceRange: range
                    )
                )
            }

            for sentenceRange in sentenceRanges {
                let sentenceEnd = NSMaxRange(sentenceRange)
                if let start = groupStart,
                   sentenceEnd - start > maximumUTF16Length,
                   groupEnd > start {
                    appendGroup()
                    groupStart = sentenceRange.location
                } else if groupStart == nil {
                    groupStart = sentenceRange.location
                }
                groupEnd = sentenceEnd
            }
            appendGroup()
        }

        return output
    }
}
