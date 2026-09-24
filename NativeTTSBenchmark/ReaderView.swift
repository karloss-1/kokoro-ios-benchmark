import SwiftUI

struct ReaderView: View {
    let library: LibraryController
    let document: LibraryDocument
    let content: ReadingDocument
    @State private var typography = false
    @State private var navigation = false
    @State private var dragging = false
    @State private var draggedProgress = 0.0
    @State private var export = false
    private var speech: SpeechEngine { library.speech }
    private var currentSection: ReadingSection? {
        guard let unit = speech.currentUnit, content.sections.indices.contains(unit.section) else { return nil }
        return content.sections[unit.section]
    }
    var body: some View {
        let grouped = Dictionary(grouping: speech.units) { "\($0.section):\($0.paragraph)" }
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(document.title).font(.title.bold())
                        if let title = currentSection?.title { Text(title).font(.title3).foregroundStyle(.secondary) }
                        Text(speech.positionLabel).font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.bottom, 12)
                    ForEach(Array(content.sections.enumerated()), id: \.element.id) { sectionIndex, section in
                        if let title = section.title { Text(title).font(.system(size: library.settings.fontSize + 5, weight: .bold, design: .serif)) }
                        if let page = section.pageNumber { Text("Page \(page)").font(.caption).foregroundStyle(.secondary) }
                        if section.paragraphs.isEmpty { Text("No text on this page.").font(.caption).foregroundStyle(.secondary) }
                        ForEach(Array(section.paragraphs.enumerated()), id: \.element.id) { paragraphIndex, paragraph in
                            ReaderParagraphView(paragraph: paragraph, units: grouped["\(sectionIndex):\(paragraphIndex)"] ?? [], activeIndex: library.settings.highlight ? speech.index : nil, fontSize: library.settings.fontSize)
                                .id(paragraph.id)
                        }
                    }
                }.padding(22).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }.environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "reader", let value = Int(url.lastPathComponent) else { return .discarded }
                speech.seek(to: value, resume: true)
                return .handled
            })
            .onChange(of: speech.index) { _, _ in
                guard library.settings.autoScroll, let unit = speech.currentUnit else { return }
                let id = content.sections[unit.section].paragraphs[unit.paragraph].id
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
            .onAppear {
                guard let unit = speech.currentUnit else { return }
                proxy.scrollTo(content.sections[unit.section].paragraphs[unit.paragraph].id, anchor: .center)
            }
        }
        .safeAreaInset(edge: .bottom) { playbackBar }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Document navigation", systemImage: "book") { navigation = true }
                Button("Typography", systemImage: "textformat.size") { typography = true }
                Menu {
                    Button("Export Text…", systemImage: "square.and.arrow.up") { export = true }
                    Button("Stop reading", systemImage: "stop") { speech.stop() }
                } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Document actions")
            }
        }
        .sheet(isPresented: $typography) {
            NavigationStack {
                Form { Slider(value: Binding(get: { library.settings.fontSize }, set: { library.settings.fontSize = $0 }), in: 16...34, step: 1) { Text("Text size") }; Text("Readable text").font(.system(size: library.settings.fontSize, design: .serif)) }
                    .navigationTitle("Text size").toolbar { Button("Done") { typography = false } }
            }.presentationDetents([.medium])
        }
        .sheet(isPresented: $navigation) {
            NavigationStack {
                List(Array(content.sections.enumerated()), id: \.element.id) { index, section in
                    Button(section.title ?? section.pageNumber.map { "Page \($0)" } ?? "Text") {
                        if let unit = speech.units.first(where: { $0.section == index }) { speech.seek(to: unit.id) }
                        navigation = false
                    }.disabled(section.paragraphs.isEmpty)
                }.navigationTitle("Contents").toolbar { Button("Done") { navigation = false } }
            }
        }
        .fileExporter(isPresented: $export, document: TextExport(text: content.exportedText), contentType: .plainText, defaultFilename: document.title.replacingOccurrences(of: "/", with: "-")) { result in
            if case .failure(let error) = result { library.error = error.localizedDescription }
        }
        .onDisappear { library.savePosition() }
    }
    private var playbackBar: some View {
        VStack(spacing: 12) {
            Slider(value: Binding(get: { dragging ? draggedProgress : speech.progress }, set: { draggedProgress = $0 }), in: 0...1) { editing in
                if editing { draggedProgress = speech.progress; dragging = true }
                else { dragging = false; speech.seek(progress: draggedProgress) }
            }.accessibilityLabel("Document position").accessibilityValue("\(Int(speech.progress * 100)) percent")
            HStack { Text("\(Int((dragging ? draggedProgress : speech.progress) * 100))% complete"); Spacer(); Text(speech.positionLabel) }.font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                navigationButton("Previous paragraph", "backward.end.alt") { speech.paragraph(-1) }
                navigationButton("Previous sentence", "backward.end.fill") { speech.sentence(-1) }
                Button { speech.isPlaying ? speech.pause() : speech.play() } label: {
                    Image(systemName: speech.isPlaying ? "pause.fill" : "play.fill").font(.title).foregroundStyle(.white).frame(width: 68, height: 68).background(ReaderStyle.green, in: Circle())
                }.accessibilityLabel(speech.isPlaying ? "Pause" : "Play").accessibilityIdentifier("readerPlayPause")
                navigationButton("Next sentence", "forward.end.fill") { speech.sentence(1) }
                navigationButton("Next paragraph", "forward.end.alt") { speech.paragraph(1) }
            }
            Menu {
                ForEach([0.75, 1, 1.25, 1.5, 2], id: \.self) { value in
                    Button("\(value.formatted())×") { library.settings.rate = value; speech.configure(voiceID: library.settings.voiceID, rate: value) }
                }
            } label: { Label("\(library.settings.rate.formatted())×", systemImage: "tortoise").font(.subheadline.weight(.medium)) }
            if let error = speech.error { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding(.horizontal, 20).padding(.vertical, 12).frame(maxWidth: 760)
            .frame(maxWidth: .infinity).background(.regularMaterial)
    }
    private func navigationButton(_ label: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) { Image(systemName: symbol).font(.title3); Text(label).font(.system(size: 10)).multilineTextAlignment(.center).lineLimit(2) }.frame(maxWidth: .infinity, minHeight: 54)
        }.foregroundStyle(.primary).accessibilityLabel(label)
    }
}

private struct ReaderParagraphView: View {
    let paragraph: ReadingParagraph
    let units: [ReadingUnit]
    let activeIndex: Int?
    let fontSize: Double
    var attributed: AttributedString {
        var text = AttributedString(paragraph.text)
        var searchStart = paragraph.text.startIndex
        for unit in units {
            guard let range = paragraph.text.range(of: unit.text, range: searchStart..<paragraph.text.endIndex),
                  let lower = AttributedString.Index(range.lowerBound, within: text),
                  let upper = AttributedString.Index(range.upperBound, within: text) else { continue }
            text[lower..<upper].link = URL(string: "reader://sentence/\(unit.id)")
            text[lower..<upper].foregroundColor = .primary
            if activeIndex == unit.id { text[lower..<upper].backgroundColor = ReaderStyle.green.opacity(0.13) }
            searchStart = range.upperBound
        }
        return text
    }
    var body: some View {
        Text(attributed).font(.system(size: fontSize, design: .serif)).lineSpacing(6).tint(.primary).frame(maxWidth: .infinity, alignment: .leading)
    }
}
