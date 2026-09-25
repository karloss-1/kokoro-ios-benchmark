import Foundation

/// Serial filesystem work keeps large JSON/source reads off the main actor.
actor LibraryStorage {
    static let shared = LibraryStorage()
    let root: URL
    init(root: URL? = nil) {
        self.root = root ?? URL.applicationSupportDirectory.appending(path: "ReaderLibrary", directoryHint: .isDirectory)
    }
    func folder(_ id: UUID) -> URL { root.appending(path: id.uuidString, directoryHint: .isDirectory) }
    func file(_ id: UUID, _ name: String) -> URL { folder(id).appending(path: name) }
    func save(id: UUID, content: ReadingDocument, source: URL? = nil, thumbnail: Data? = nil) throws -> (String?, String?) {
        let fm = FileManager.default
        let destination = folder(id)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            // Set the directory protection before creating files so they inherit it.
            try fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
            try Task.checkCancellation()
            var sourceName: String?
            if let source {
                sourceName = source.lastPathComponent
                let target = destination.appending(path: source.lastPathComponent)
                if source.standardizedFileURL != target.standardizedFileURL { try fm.copyItem(at: source, to: target) }
            }
            try Task.checkCancellation()
            try JSONEncoder().encode(content).write(to: file(id, "content.json"), options: .atomic)
            if let thumbnail { try thumbnail.write(to: file(id, "cover.jpg"), options: .atomic) }
            try Task.checkCancellation()
            return (sourceName, thumbnail == nil ? nil : "cover.jpg")
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
    }
    func load(_ id: UUID) throws -> ReadingDocument {
        let url = file(id, "content.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw ReaderError.missingFile }
        let document = try JSONDecoder().decode(ReadingDocument.self, from: Data(contentsOf: url))
        guard document.schemaVersion == 1 else { throw ReaderError.message("This saved document uses an unsupported format.") }
        return document
    }
    func thumbnail(_ id: UUID) -> Data? { try? Data(contentsOf: file(id, "cover.jpg")) }
    func remove(_ id: UUID) throws {
        let url = folder(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    func createText(_ text: String) throws -> ReadingDocument {
        try DocumentNormalizer.document(sections: [DocumentNormalizer.section(text: text)])
    }
    func stage(_ url: URL) throws -> URL {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let directory = FileManager.default.temporaryDirectory.appending(path: "ReaderImport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appending(path: url.lastPathComponent)
        do { try FileManager.default.copyItem(at: url, to: target); return target }
        catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
    func discardStaged(_ url: URL) {
        let parent = url.deletingLastPathComponent()
        guard parent.lastPathComponent.hasPrefix("ReaderImport-") else { return }
        try? FileManager.default.removeItem(at: parent)
    }
}
