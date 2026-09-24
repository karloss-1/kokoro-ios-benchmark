import AVFoundation

enum PlaybackState: String {
    case ready, speaking, paused, interrupted, finished, stopped, failed
}

enum VoiceFilter: String, CaseIterable, Identifiable {
    case spanish = "Spanish", english = "English", all = "All"
    var id: String { rawValue }
    func includes(_ voice: AVSpeechSynthesisVoice) -> Bool {
        switch self { case .spanish: voice.language.hasPrefix("es"); case .english: voice.language.hasPrefix("en"); case .all: true }
    }
}
extension AVSpeechSynthesisVoice {
    var qualityLabel: String {
        switch quality { case .default: "Default"; case .enhanced: "Enhanced"; case .premium: "Premium"; @unknown default: "Unknown" }
    }
}
