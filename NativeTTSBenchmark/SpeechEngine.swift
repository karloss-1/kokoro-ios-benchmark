import AVFoundation
import Combine
import Foundation
import UIKit

final class SpeechEngine: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var sourceText = TestCorpus.spanishShort
    @Published private(set) var sourceLabel = SampleText.spanishShort.rawValue
    @Published private(set) var voices: [AVSpeechSynthesisVoice] = []
    @Published var voiceFilter: VoiceFilter = .spanish
    @Published var selectedVoiceIdentifier = ""
    @Published var selectedRate: SpeechRatePreset = .normal
    @Published private(set) var playbackState: PlaybackState = .ready
    @Published private(set) var segments: [SpeechSegment] = []
    @Published private(set) var currentSegmentIndex: Int?
    @Published private(set) var currentSpokenRange: NSRange?
    @Published private(set) var latestEvent = "Not started"
    @Published private(set) var lastError: String?
    @Published private(set) var recentEvents: [String] = []
    @Published private(set) var audioSessionSummary = "Not activated"

    private let synthesizer = AVSpeechSynthesizer()
    private var activeUtterance: AVSpeechUtterance?
    private var activeVoice: AVSpeechSynthesisVoice?
    private var activeRate: Float = AVSpeechUtteranceDefaultSpeechRate
    private var interruptionIsActive = false
    private var stopWasRequested = false
    private var notificationObservers: [NSObjectProtocol] = []

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
        installAudioObservers()
        refreshVoices()
    }

    deinit {
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
    }

    var selectedVoice: AVSpeechSynthesisVoice? {
        voices.first { $0.identifier == selectedVoiceIdentifier }
    }

    var visibleVoices: [AVSpeechSynthesisVoice] {
        switch voiceFilter {
        case .spanish:
            voices.filter { $0.language.lowercased().hasPrefix("es") }
        case .english:
            voices.filter { $0.language.lowercased().hasPrefix("en") }
        case .all:
            voices
        }
    }

    var wordCount: Int {
        sourceText.split(whereSeparator: \.isWhitespace).count
    }

    var paragraphCount: Int {
        Set(segments.map(\.paragraph)).count
    }

    var currentSegmentLabel: String {
        guard let currentSegmentIndex, segments.indices.contains(currentSegmentIndex) else {
            return "—"
        }
        let segment = segments[currentSegmentIndex]
        return "P\(segment.paragraph) · \(currentSegmentIndex + 1)/\(segments.count)"
    }

    var canPause: Bool { playbackState == .speaking }
    var canResume: Bool { playbackState == .paused || playbackState == .interrupted }
    var canStop: Bool { playbackState.isActive }
    var canStart: Bool { !playbackState.isActive }

    func refreshVoices() {
        voices = AVSpeechSynthesisVoice.speechVoices().sorted(by: Self.voiceSort)
        if !voices.contains(where: { $0.identifier == selectedVoiceIdentifier }) {
            selectedVoiceIdentifier =
                voices.first(where: { $0.language.caseInsensitiveCompare("es-MX") == .orderedSame })?.identifier
                ?? voices.first(where: { $0.language.lowercased().hasPrefix("es") })?.identifier
                ?? voices.first(where: {
                    $0.language.caseInsensitiveCompare(AVSpeechSynthesisVoice.currentLanguageCode()) == .orderedSame
                })?.identifier
                ?? voices.first?.identifier
                ?? ""
        }
        record("Voice list refreshed", detail: "\(voices.count) voices")
    }

    func selectVoice(_ voice: AVSpeechSynthesisVoice) {
        guard !playbackState.isActive else { return }
        selectedVoiceIdentifier = voice.identifier
        record("Voice selected", detail: "\(voice.name) · \(voice.language)")
    }

    func load(_ sample: SampleText) {
        guard !playbackState.isActive else { return }
        sourceText = sample.text
        sourceLabel = sample.rawValue
        clearProgress()
        lastError = nil
        playbackState = .ready
    }

    func updateCustomText(_ text: String) {
        guard !playbackState.isActive else { return }
        sourceText = text
        sourceLabel = "Custom text"
        clearProgress()
    }

    func speak() {
        guard !playbackState.isActive else { return }
        guard let voice = selectedVoice else {
            fail("No available voice is selected. Refresh the voice list or install an iOS voice.")
            return
        }

        let newSegments = TextSegmenter.segments(in: sourceText)
        guard !newSegments.isEmpty else {
            fail("Enter or select text before starting speech.")
            return
        }

        do {
            try activateAudioSession()
        } catch {
            fail("Could not activate AVAudioSession: \(error.localizedDescription)")
            return
        }

        segments = newSegments
        activeVoice = voice
        activeRate = selectedRate.avSpeechRate
        currentSegmentIndex = 0
        currentSpokenRange = nil
        lastError = nil
        interruptionIsActive = false
        stopWasRequested = false
        playbackState = .speaking
        record(
            "Speak requested",
            detail: "\(voice.name) · \(voice.language) · AVSpeechUtterance.rate \(Self.rateString(activeRate)) · \(newSegments.count) segments"
        )
        speakCurrentSegment()
    }

    func pause() {
        guard synthesizer.pauseSpeaking(at: .immediate) else {
            record("Pause request not accepted", detail: "synthesizer was not speaking")
            return
        }
        record("Pause requested")
    }

    func resume() {
        guard synthesizer.continueSpeaking() else {
            record("Resume request not accepted", detail: "system did not resume this utterance")
            lastError = "Resume was not accepted by AVSpeechSynthesizer. Try Stop, then Speak again."
            return
        }
        interruptionIsActive = false
        record("Resume requested")
    }

    func stop() {
        guard playbackState.isActive else { return }
        stopWasRequested = true
        currentSpokenRange = nil
        if synthesizer.stopSpeaking(at: .immediate) {
            playbackState = .stopping
            record("Stop requested")
        } else {
            activeUtterance = nil
            currentSegmentIndex = nil
            playbackState = .stopped
            record("Stopped without active utterance")
            deactivateAudioSession()
        }
    }

    func recordAppState(_ phase: String) {
        record("App state", detail: phase)
    }

    func qualityLabel(for voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .default: "Default"
        case .enhanced: "Enhanced"
        case .premium: "Premium"
        @unknown default: "Unknown"
        }
    }

    private func speakCurrentSegment() {
        guard let currentSegmentIndex,
              segments.indices.contains(currentSegmentIndex),
              let activeVoice else {
            finishRun()
            return
        }

        let segment = segments[currentSegmentIndex]
        let utterance = AVSpeechUtterance(string: segment.text)
        utterance.voice = activeVoice
        utterance.rate = activeRate
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0
        activeUtterance = utterance
        currentSpokenRange = nil
        synthesizer.speak(utterance)
    }

    private func finishCurrentSegment() {
        guard let currentSegmentIndex else {
            finishRun()
            return
        }
        let nextIndex = currentSegmentIndex + 1
        if segments.indices.contains(nextIndex) {
            self.currentSegmentIndex = nextIndex
            speakCurrentSegment()
        } else {
            finishRun()
        }
    }

    private func finishRun() {
        activeUtterance = nil
        currentSpokenRange = nil
        playbackState = .finished
        record("Reading finished")
        deactivateAudioSession()
    }

    private func clearProgress() {
        segments = []
        currentSegmentIndex = nil
        currentSpokenRange = nil
    }

    private func activateAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [])
        try session.setActive(true)
        audioSessionSummary = "playback · spokenAudio · no options"
        record("Audio session active", detail: audioSessionSummary)
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: [.notifyOthersOnDeactivation]
            )
            audioSessionSummary = "Inactive"
            record("Audio session deactivated")
        } catch {
            lastError = "Audio session deactivation: \(error.localizedDescription)"
            record("Audio session deactivation error", detail: error.localizedDescription)
        }
    }

    private func installAudioObservers() {
        let center = NotificationCenter.default
        notificationObservers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] notification in
                self?.handleInterruption(notification)
            }
        )
        notificationObservers.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] notification in
                self?.handleRouteChange(notification)
            }
        )
    }

    private func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            record("Audio interruption", detail: "unavailable type")
            return
        }

        switch type {
        case .began:
            interruptionIsActive = true
            let accepted = synthesizer.pauseSpeaking(at: .immediate)
            playbackState = .interrupted
            record("Audio interruption began", detail: accepted ? "speech pause requested" : "speech pause unavailable")
        case .ended:
            let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            interruptionIsActive = false
            if synthesizer.isPaused {
                playbackState = .paused
            } else if synthesizer.isSpeaking {
                playbackState = .speaking
            }
            record("Audio interruption ended", detail: "resume hint \(options.map(String.init) ?? "unavailable"); resume is manual")
        @unknown default:
            record("Audio interruption", detail: "unknown type \(rawType)")
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).map(String.init) ?? "unavailable"
        record("Audio route changed", detail: "reason \(reason)")
    }

    private func fail(_ message: String) {
        lastError = message
        playbackState = .failed
        record("Error", detail: message)
        deactivateAudioSession()
    }

    private func record(_ event: String, detail: String? = nil) {
        let timestamp = Date.now.formatted(date: .omitted, time: .standard)
        let line = detail.map { "\(timestamp) · \(event): \($0)" } ?? "\(timestamp) · \(event)"
        latestEvent = event
        recentEvents.insert(line, at: 0)
        recentEvents = Array(recentEvents.prefix(6))
        print("[NativeTTSBenchmark] \(line)")
    }

    private func onMain(_ action: @escaping (SpeechEngine) -> Void) {
        if Thread.isMainThread {
            action(self)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                action(self)
            }
        }
    }

    private static func voiceSort(_ left: AVSpeechSynthesisVoice, _ right: AVSpeechSynthesisVoice) -> Bool {
        func priority(_ language: String) -> Int {
            let normalized = language.lowercased()
            if normalized == "es-mx" { return 0 }
            if normalized.hasPrefix("es") { return 1 }
            if normalized.hasPrefix("en") { return 2 }
            return 3
        }
        let leftPriority = priority(left.language)
        let rightPriority = priority(right.language)
        if leftPriority != rightPriority { return leftPriority < rightPriority }
        if left.language != right.language {
            return left.language.localizedStandardCompare(right.language) == .orderedAscending
        }
        return left.name.localizedStandardCompare(right.name) == .orderedAscending
    }

    private static func rateString(_ rate: Float) -> String {
        String(format: "%.2f", rate)
    }

    // Delegate callbacks are marshalled to the main queue before publishing UI state.
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        onMain { engine in
            guard engine.activeUtterance === utterance else { return }
            engine.playbackState = engine.interruptionIsActive ? .interrupted : .speaking
            engine.record("didStart", detail: engine.currentSegmentLabel)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        onMain { engine in
            guard engine.activeUtterance === utterance,
                  let index = engine.currentSegmentIndex,
                  engine.segments.indices.contains(index) else { return }
            let sourceStart = engine.segments[index].sourceRange.location
            engine.currentSpokenRange = NSRange(
                location: sourceStart + characterRange.location,
                length: characterRange.length
            )
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        onMain { engine in
            guard engine.activeUtterance === utterance else { return }
            engine.playbackState = engine.interruptionIsActive ? .interrupted : .paused
            engine.record("didPause", detail: engine.currentSegmentLabel)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        onMain { engine in
            guard engine.activeUtterance === utterance else { return }
            engine.interruptionIsActive = false
            engine.playbackState = .speaking
            engine.record("didContinue", detail: engine.currentSegmentLabel)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onMain { engine in
            guard engine.activeUtterance === utterance else { return }
            engine.record("didFinish", detail: engine.currentSegmentLabel)
            engine.activeUtterance = nil
            engine.currentSpokenRange = nil
            engine.finishCurrentSegment()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onMain { engine in
            engine.record("didCancel", detail: engine.currentSegmentLabel)
            guard engine.activeUtterance === utterance else { return }
            engine.activeUtterance = nil
            engine.currentSpokenRange = nil
            engine.currentSegmentIndex = nil
            engine.playbackState = engine.stopWasRequested ? .stopped : .failed
            if !engine.stopWasRequested {
                engine.lastError = "AVSpeechSynthesizer cancelled the active utterance."
            }
            engine.stopWasRequested = false
            engine.deactivateAudioSession()
        }
    }
}
