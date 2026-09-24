import SwiftData
import SwiftUI
import Observation

@MainActor @Observable final class LibraryController {
    let container: ModelContainer
    let settings = ReaderSettings()
    let speech = SpeechEngine()
    var documents: [LibraryDocument] = []
    var opened: LibraryDocument?
    var content: ReadingDocument?
    var error: String?
    var isOpening = false
    @ObservationIgnored private var openingToken = UUID()
    @ObservationIgnored private var media: SystemMedia?
    var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
        refresh()
        speech.positionChanged = { [weak self] in self?.savePosition() }
        media = SystemMedia(speech: speech)
        speech.playbackChanged = { [weak self] in self?.media?.update() }
    }
    func refresh() {
        do { documents = try context.fetch(FetchDescriptor<LibraryDocument>(sortBy: [SortDescriptor(\.importedAt, order: .reverse)])) }
        catch { self.error = error.localizedDescription }
    }
    func add(title: String, kind: SourceKind, content: ReadingDocument, source: URL? = nil, thumbnail: Data? = nil) async throws {
        let id = UUID()
        let names = try await LibraryStorage.shared.save(id: id, content: content, source: source, thumbnail: thumbnail)
        do { try Task.checkCancellation() } catch { try? await LibraryStorage.shared.remove(id); throw error }
        let record = LibraryDocument(id: id, title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : title,
                                     kind: kind, sourceFilename: names.0, thumbnailFilename: names.1, content: content)
        context.insert(record)
        do { try context.save(); refresh() }
        catch { context.delete(record); try? await LibraryStorage.shared.remove(id); throw error }
    }
    func open(_ document: LibraryDocument, play: Bool = false) async {
        let token = UUID()
        openingToken = token
        isOpening = true
        defer { if openingToken == token { isOpening = false } }
        do {
            let loaded = try await LibraryStorage.shared.load(document.id)
            guard openingToken == token, documents.contains(where: { $0.id == document.id }) else { return }
            if speech.documentID != document.id {
                savePosition()
                speech.load(id: document.id, title: document.title, content: loaded, position: document.sentenceIndex, completed: document.progress >= 1)
            }
            opened = document
            content = loaded
            document.lastOpenedAt = .now
            try context.save()
            speech.configure(voiceID: settings.voiceID, rate: settings.rate)
            if play { speech.play() }
        } catch { self.error = error.localizedDescription }
    }
    func savePosition() {
        guard let id = speech.documentID, let document = documents.first(where: { $0.id == id }) else { return }
        document.sentenceIndex = speech.index
        document.progress = speech.progress
        if let unit = speech.currentUnit {
            document.sectionIndex = unit.section
            document.paragraphIndex = unit.paragraph
            document.pageNumber = speech.content?.sections[unit.section].pageNumber
            document.sectionTitle = speech.content?.sections[unit.section].title
        }
        do { try context.save() } catch { self.error = "Could not save reading position: \(error.localizedDescription)" }
    }
    func rename(_ document: LibraryDocument, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        document.title = title
        do { try context.save() } catch { self.error = error.localizedDescription }
    }
    func delete(_ document: LibraryDocument) async {
        if speech.documentID == document.id { speech.unload(); opened = nil; content = nil }
        do {
            try await LibraryStorage.shared.remove(document.id)
            context.delete(document)
            try context.save()
            refresh()
        } catch { self.error = error.localizedDescription }
    }
}
