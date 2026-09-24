import AVFoundation
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: ReaderSettings
    let speech: SpeechEngine
    var selectedVoice: AVSpeechSynthesisVoice? { speech.voices.first { $0.identifier == settings.voiceID } }
    var body: some View {
        NavigationStack {
            Form {
                Section("Voice") {
                    NavigationLink { VoicePicker(settings: settings, speech: speech) } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text(selectedVoice?.name ?? "Automatic")
                                Text(selectedVoice.map { Locale.current.localizedString(forIdentifier: $0.language) ?? $0.language } ?? "Match document language")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "waveform").foregroundStyle(ReaderStyle.green) }
                    }
                }
                Section {
                    HStack {
                        Image(systemName: "tortoise.fill")
                        Slider(value: $settings.rate, in: 0.75...2, step: 0.25).accessibilityLabel("Speaking rate")
                        Image(systemName: "hare.fill")
                    }.foregroundStyle(.secondary)
                } header: { HStack { Text("Speaking rate"); Spacer(); Text(settings.rate.formatted(.number.precision(.fractionLength(2))) + "×") } }
                Section("Reading") {
                    Toggle(isOn: $settings.highlight) { Label("Highlight text while reading", systemImage: "book") }
                    Toggle(isOn: $settings.autoScroll) { Label("Auto-scroll", systemImage: "list.bullet") }
                }
                Section("Appearance") {
                    HStack(spacing: 8) {
                        ForEach(["System", "Light", "Dark"], id: \.self) { appearance in
                            Button { settings.appearance = appearance } label: {
                                VStack(spacing: 10) {
                                    Image(systemName: appearance == "Dark" ? "moon.fill" : appearance == "Light" ? "sun.max" : "circle.lefthalf.filled").font(.title2)
                                    Text(appearance).font(.subheadline)
                                }.frame(maxWidth: .infinity).padding(.vertical, 14)
                                    .background(settings.appearance == appearance ? ReaderStyle.paleGreen : ReaderStyle.background, in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(settings.appearance == appearance ? ReaderStyle.green : .clear))
                            }.buttonStyle(.plain).foregroundStyle(settings.appearance == appearance ? ReaderStyle.green : .secondary)
                                .accessibilityAddTraits(settings.appearance == appearance ? .isSelected : [])
                        }
                    }
                }
            }.navigationTitle("Settings")
                .onChange(of: settings.rate) { _, _ in speech.configure(voiceID: settings.voiceID, rate: settings.rate) }
                .onChange(of: settings.voiceID) { _, _ in speech.configure(voiceID: settings.voiceID, rate: settings.rate) }
        }
    }
}
struct VoicePicker: View {
    @Bindable var settings: ReaderSettings
    let speech: SpeechEngine
    @State private var filter: VoiceFilter = .spanish
    var body: some View {
        List {
            Picker("Language", selection: $filter) { ForEach(VoiceFilter.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            Button { settings.voiceID = "" } label: {
                HStack { Text("Automatic · document language"); Spacer(); if settings.voiceID.isEmpty { Image(systemName: "checkmark") } }
            }
            ForEach(speech.voices.filter(filter.includes), id: \.identifier) { voice in
                Button { settings.voiceID = voice.identifier } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(voice.name).font(.headline).foregroundStyle(.primary)
                            Text("\(voice.language) · \(voice.qualityLabel)").font(.subheadline).foregroundStyle(.secondary)
                            Text(voice.identifier).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if voice.identifier == settings.voiceID { Image(systemName: "checkmark") }
                    }
                }
            }
        }.navigationTitle("Voice").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { speech.refreshVoices() } }
    }
}
