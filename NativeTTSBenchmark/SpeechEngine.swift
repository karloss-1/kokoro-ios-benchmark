import AVFoundation
import Foundation
import Observation

/// Evolves the validated benchmark: one retained synthesizer, one utterance at a time,
/// identity-filtered callbacks, and the same playback/spokenAudio session.
@MainActor @Observable final class SpeechEngine: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var voices: [AVSpeechSynthesisVoice] = []
    private(set) var state: PlaybackState = .ready
    private(set) var documentID: UUID?
    private(set) var title = ""
    private(set) var content: ReadingDocument?
    private(set) var units: [ReadingUnit] = []
    private(set) var index = 0
    private(set) var error: String?
    private(set) var latestEvent = "Ready"
    private(set) var actualVoice: AVSpeechSynthesisVoice?
    private(set) var rate: Double = 1
    @ObservationIgnored var positionChanged: (() -> Void)?
    @ObservationIgnored var playbackChanged: (() -> Void)?
    @ObservationIgnored private var synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var activeUtterance: AVSpeechUtterance?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    private var selectedVoiceID = ""
    private var wantsPlayback = false
    private var interrupted = false
    private var totalCharacters = 0

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
        refreshVoices()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor [weak self] in self?.handleInterruption(type) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor [weak self] in
                if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self?.pause() }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.resetAudioServices() }
        })
    }
    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        synthesizer.delegate = nil
        synthesizer.stopSpeaking(at: .immediate)
    }
    var currentUnit: ReadingUnit? { units.indices.contains(index) ? units[index] : nil }
    var isPlaying: Bool { state == .speaking }
    var progress: Double {
        if state == .finished { return 1 }
        guard totalCharacters > 0, let currentUnit else { return 0 }
        return Double(currentUnit.characterOffset) / Double(totalCharacters)
    }
    var positionLabel: String {
        guard let currentUnit, let content else { return "" }
        let section = content.sections[currentUnit.section]
        if let page = section.pageNumber { return "Page \(page) of \(content.originalPageCount ?? page)" }
        return "Sentence \(index + 1) of \(units.count)"
    }
    func refreshVoices() {
        voices = AVSpeechSynthesisVoice.speechVoices().sorted {
            func rank(_ language: String) -> Int { language.lowercased() == "es-mx" ? 0 : language.hasPrefix("es") ? 1 : language.hasPrefix("en") ? 2 : 3 }
            if rank($0.language) != rank($1.language) { return rank($0.language) < rank($1.language) }
            return ($0.language + $0.name).localizedStandardCompare($1.language + $1.name) == .orderedAscending
        }
    }
    func configure(voiceID: String, rate: Double) {
        let changed = selectedVoiceID != voiceID || self.rate != rate
        selectedVoiceID = voiceID
        self.rate = min(2, max(0.75, rate))
        if changed, !units.isEmpty { seek(to: index, resume: isPlaying) }
    }
    func load(id: UUID, title: String, content: ReadingDocument, position: Int, completed: Bool) {
        stop()
        documentID = id
        self.title = title
        self.content = content
        units = content.units
        totalCharacters = units.reduce(0) { $0 + $1.text.count }
        index = min(max(0, position), max(0, units.count - 1))
        state = completed ? .finished : .ready
        error = nil
    }
    func unload() { stop(); documentID = nil; content = nil; units = []; playbackChanged?() }
    func play() {
        guard !units.isEmpty, !interrupted else { return }
        error = nil
        do {
            try activateAudioSession()
            wantsPlayback = true
            if state == .finished { index = 0 }
            if synthesizer.isPaused, activeUtterance != nil, synthesizer.continueSpeaking() {
                state = .speaking
                playbackChanged?()
                return
            }
            invalidateUtterance()
            speakCurrent()
        } catch { fail("Audio could not start: \(error.localizedDescription)") }
    }
    func pause() {
        guard isPlaying else { return }
        wantsPlayback = false
        if !synthesizer.pauseSpeaking(at: .immediate) { invalidateUtterance() }
        state = .paused
        notify("Paused")
    }
    func stop() {
        wantsPlayback = false
        invalidateUtterance()
        state = .stopped
        deactivateAudioSession()
        notify("Stopped")
    }
    func seek(to destination: Int, resume: Bool? = nil) {
        guard !units.isEmpty else { return }
        let shouldPlay = resume ?? isPlaying
        wantsPlayback = false
        invalidateUtterance()
        index = min(max(destination, 0), units.count - 1)
        state = .paused
        notify("Position changed")
        if shouldPlay { play() }
    }
    func seek(progress: Double) {
        let target = Int(min(1, max(0, progress)) * Double(totalCharacters))
        let nearest = units.min { abs($0.characterOffset - target) < abs($1.characterOffset - target) }?.id ?? 0
        seek(to: nearest)
    }
    func sentence(_ delta: Int) { seek(to: index + delta) }
    func paragraph(_ delta: Int) {
        guard let currentUnit else { return }
        let starts = units.filter { unit in
            unit.id == 0 || units[unit.id - 1].section != unit.section || units[unit.id - 1].paragraph != unit.paragraph
        }
        let target: ReadingUnit?
        if delta > 0 { target = starts.first { $0.id > index && ($0.section != currentUnit.section || $0.paragraph != currentUnit.paragraph) } }
        else { target = starts.last { $0.id < index && ($0.section != currentUnit.section || $0.paragraph != currentUnit.paragraph) } ?? starts.first }
        if let target { seek(to: target.id) }
    }
    private func speakCurrent() {
        guard let unit = currentUnit else { return }
        refreshVoices()
        let language = content?.language ?? "es"
        let voice = AVSpeechSynthesisVoice(identifier: selectedVoiceID)
            ?? voices.first { $0.language.hasPrefix(language) }
            ?? AVSpeechSynthesisVoice(language: language)
            ?? voices.first
        guard let voice else { fail("No system voice is available. Install a voice in iOS Settings and try again."); return }
        actualVoice = voice
        let utterance = AVSpeechUtterance(string: unit.text)
        utterance.voice = voice
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(rate)))
        activeUtterance = utterance
        state = .speaking
        synthesizer.speak(utterance)
        notify("Speaking sentence \(index + 1)")
    }
    private func invalidateUtterance() {
        // Clear identity BEFORE stop; a delayed didCancel for the old utterance must
        // never cancel or advance a new seek/voice/rate request.
        activeUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
    }
    private func activateAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [])
        try session.setActive(true)
    }
    private func deactivateAudioSession() {
        do { try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        catch { print("[Reader] Audio deactivation: \(error)") }
    }
    private func handleInterruption(_ type: UInt?) {
        guard let type else { return }
        if type == AVAudioSession.InterruptionType.began.rawValue {
            guard state == .speaking || state == .paused else { return }
            pause(); interrupted = true; state = .interrupted; notify("Audio interrupted")
        } else {
            interrupted = false
            if state == .interrupted { state = .paused; notify("Interruption ended; ready to resume") }
        }
    }
    private func resetAudioServices() {
        invalidateUtterance()
        synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
        wantsPlayback = false
        interrupted = false
        state = .paused
        notify("Audio services reset; ready to resume")
    }
    private func fail(_ message: String) { error = message; wantsPlayback = false; state = .failed; deactivateAudioSession(); notify(message) }
    private func notify(_ event: String) { latestEvent = event; print("[Reader] \(event)"); positionChanged?(); playbackChanged?() }
    private func receive(_ event: String, id: ObjectIdentifier) {
        guard let activeUtterance, ObjectIdentifier(activeUtterance) == id else { return }
        switch event {
        case "didFinish":
            self.activeUtterance = nil
            if index + 1 < units.count {
                index += 1
                if wantsPlayback { speakCurrent() } else { state = .paused; notify("Paused at next sentence") }
            } else { state = .finished; wantsPlayback = false; deactivateAudioSession(); notify("Reading complete") }
        case "didCancel": self.activeUtterance = nil; fail("Speech was cancelled by the system. Tap Play to resume this sentence.")
        case "didPause": state = .paused; notify(event)
        case "didContinue", "didStart": if wantsPlayback { state = .speaking }; notify(event)
        default: break
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) { relay("didStart", utterance) }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { relay("didFinish", utterance) }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) { relay("didPause", utterance) }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) { relay("didContinue", utterance) }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { relay("didCancel", utterance) }
    nonisolated private func relay(_ event: String, _ utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.receive(event, id: id) }
    }
}
