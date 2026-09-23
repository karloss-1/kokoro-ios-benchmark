import AVFoundation
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var engine = SpeechEngine()
    @Environment(\.scenePhase) private var scenePhase

    private var highlightedText: AttributedString {
        var text = AttributedString(engine.sourceText)
        guard let range = engine.currentSpokenRange,
              let attributedRange = Range(range, in: text) else {
            return text
        }
        text[attributedRange].backgroundColor = Color.yellow.opacity(0.42)
        text[attributedRange].font = .system(size: 16, weight: .semibold)
        return text
    }

    private var editableText: Binding<String> {
        Binding(
            get: { engine.sourceText },
            set: { engine.updateCustomText($0) }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    deviceCard
                    voiceCard
                    textCard
                    playbackCard
                    diagnosticsCard
                    privacyNote
                }
                .padding(16)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Native TTS Benchmark")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: scenePhase) { _, phase in
                engine.recordAppState(String(describing: phase))
            }
        }
    }

    private var deviceCard: some View {
        card {
            sectionTitle("Device", icon: "iphone")
            diagnosticRow("Device", value: UIDevice.current.model)
            diagnosticRow("iOS / iPadOS", value: UIDevice.current.systemVersion)
            diagnosticRow("Locale", value: Locale.current.identifier)
            diagnosticRow("Speech language", value: AVSpeechSynthesisVoice.currentLanguageCode())
        }
    }

    private var voiceCard: some View {
        card {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("Voice", icon: "waveform")
                Spacer()
                Text("\(engine.visibleVoices.count) / \(engine.voices.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Picker("Filter voices", selection: $engine.voiceFilter) {
                ForEach(VoiceFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            if engine.visibleVoices.isEmpty {
                ContentUnavailableView(
                    "No voices in this filter",
                    systemImage: "waveform.slash",
                    description: Text("Refresh the list or check which voices are installed in iOS Settings.")
                )
                .frame(minHeight: 110)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(engine.visibleVoices, id: \.identifier) { voice in
                            voiceRow(voice)
                        }
                    }
                }
                .frame(maxHeight: 240)
                .accessibilityLabel("Available voices")
            }

            Button {
                engine.refreshVoices()
            } label: {
                Label("Refresh voices", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderless)
            .disabled(engine.playbackState.isActive)
        }
    }

    private func voiceRow(_ voice: AVSpeechSynthesisVoice) -> some View {
        let isSelected = engine.selectedVoiceIdentifier == voice.identifier
        return Button {
            engine.selectVoice(voice)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(voice.name)
                            .font(.subheadline.weight(.semibold))
                        Text(voice.language)
                            .font(.caption.monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                voice.language.caseInsensitiveCompare("es-MX") == .orderedSame
                                    ? Color.orange.opacity(0.18)
                                    : Color.secondary.opacity(0.12)
                            )
                            .clipShape(Capsule())
                    }
                    Text(voice.identifier)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("Quality: \(engine.qualityLabel(for: voice))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.10)
                    : Color(uiColor: .tertiarySystemGroupedBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(engine.playbackState.isActive)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var textCard: some View {
        card {
            sectionTitle("Test text", icon: "text.alignleft")

            Menu {
                ForEach(SampleText.allCases) { sample in
                    Button(sample.rawValue) {
                        engine.load(sample)
                    }
                }
            } label: {
                HStack {
                    Label(engine.sourceLabel, systemImage: "doc.text")
                    Spacer()
                    Image(systemName: "chevron.down")
                }
                .font(.subheadline.weight(.medium))
                .padding(12)
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(engine.playbackState.isActive)

            TextEditor(text: editableText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 150, maxHeight: 230)
                .padding(8)
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .disabled(engine.playbackState.isActive)

            HStack(spacing: 14) {
                metric("\(engine.wordCount)", label: "words")
                metric("\(engine.paragraphCount)", label: "paragraphs")
                metric("\(engine.segments.count)", label: "segments")
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Current text position")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(highlightedText)
                    .font(.body)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.yellow.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Text with the current spoken range highlighted when available")
            }
        }
    }

    private var playbackCard: some View {
        card {
            sectionTitle("Playback", icon: "play.circle")
            Text("Speech rate")
                .font(.subheadline.weight(.medium))
            HStack(spacing: 6) {
                ForEach(SpeechRatePreset.allCases) { preset in
                    Button {
                        engine.selectedRate = preset
                    } label: {
                        Text(preset.label)
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                engine.selectedRate == preset
                                    ? Color.accentColor
                                    : Color(uiColor: .tertiarySystemGroupedBackground)
                            )
                            .foregroundStyle(engine.selectedRate == preset ? Color.white : Color.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .disabled(engine.playbackState.isActive)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                actionButton("Speak / Play", icon: "play.fill", prominent: true, enabled: engine.canStart) {
                    engine.speak()
                }
                actionButton("Pause", icon: "pause.fill", enabled: engine.canPause) {
                    engine.pause()
                }
                actionButton("Resume", icon: "playpause.fill", enabled: engine.canResume) {
                    engine.resume()
                }
                actionButton("Stop", icon: "stop.fill", enabled: engine.canStop) {
                    engine.stop()
                }
            }

            Text("Rate is an approximate multiplier anchored to Apple's default speech rate; it is not a measured words-per-minute value.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var diagnosticsCard: some View {
        card {
            sectionTitle("Diagnostics", icon: "waveform.path")
            diagnosticRow("Voice", value: engine.selectedVoice?.name ?? "Unavailable")
            diagnosticRow("Locale", value: engine.selectedVoice?.language ?? "Unavailable")
            diagnosticRow("Identifier", value: engine.selectedVoice?.identifier ?? "Unavailable")
            diagnosticRow("Quality", value: engine.selectedVoice.map(engine.qualityLabel(for:)) ?? "Unavailable")
            diagnosticRow(
                "Rate preset / AV rate",
                value: "\(engine.selectedRate.label) / \(String(format: "%.2f", engine.selectedRate.avSpeechRate))"
            )
            diagnosticRow("State", value: engine.playbackState.label)
            diagnosticRow("Segment", value: engine.currentSegmentLabel)
            diagnosticRow("Audio session", value: engine.audioSessionSummary)
            diagnosticRow("Last event", value: engine.latestEvent)

            if let lastError = engine.lastError {
                Text(lastError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }

            if !engine.recentEvents.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Recent events")
                        .font(.caption.weight(.semibold))
                    ForEach(Array(engine.recentEvents.enumerated()), id: \.offset) { _, event in
                        Text(event)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(2)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var privacyNote: some View {
        Text("The app has no network client and sends no text to an app server. Voice availability, quality, and offline behavior are controlled by iOS and the selected system voice.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 3)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
    }

    private func diagnosticRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.footnote)
    }

    private func metric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.subheadline.monospacedDigit().weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func actionButton(
        _ title: String,
        icon: String,
        prominent: Bool = false,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(prominent ? Color.accentColor : Color(uiColor: .tertiarySystemGroupedBackground))
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
