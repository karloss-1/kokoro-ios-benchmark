import SwiftUI
import Observation

@MainActor @Observable final class ReaderSettings {
    var voiceID: String { didSet { defaults.set(voiceID, forKey: "voiceID") } }
    var rate: Double { didSet { defaults.set(rate, forKey: "speechRate") } }
    var highlight: Bool { didSet { defaults.set(highlight, forKey: "highlight") } }
    var autoScroll: Bool { didSet { defaults.set(autoScroll, forKey: "autoScroll") } }
    var appearance: String { didSet { defaults.set(appearance, forKey: "appearance") } }
    var fontSize: Double { didSet { defaults.set(fontSize, forKey: "fontSize") } }
    @ObservationIgnored private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        voiceID = defaults.string(forKey: "voiceID") ?? ""
        let savedRate = defaults.double(forKey: "speechRate")
        rate = savedRate == 0 ? 1 : min(2, max(0.75, savedRate))
        highlight = defaults.object(forKey: "highlight") as? Bool ?? true
        autoScroll = defaults.object(forKey: "autoScroll") as? Bool ?? true
        appearance = defaults.string(forKey: "appearance") ?? "System"
        fontSize = defaults.object(forKey: "fontSize") as? Double ?? 22
    }
    var colorScheme: ColorScheme? {
        switch appearance { case "Light": .light; case "Dark": .dark; default: nil }
    }
}
