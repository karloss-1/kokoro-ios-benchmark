import Foundation
import Observation
import PhotosUI
import SwiftUI
import VisionKit

@MainActor @Observable final class ImportCoordinator {
    var processing = false
    var preparing = false
    var progress = ExtractionProgress(stage: "Importing", detail: "Preparing document…", completed: 0, total: 1)
    var pdf: PDFPreview?
    var epub: EPUBPreview?
    let epubService = EPUBService()
    var error: String?
    var title = ""
    var completed = false
    var cancelling = false
    let extractor = DocumentExtractor()
    @ObservationIgnored var work: Task<Void, Never>?
    @ObservationIgnored var stagedURL: URL?

    func preparePDF(_ url: URL) {
        processing = true; preparing = true; title = url.lastPathComponent
        work = Task {
            do {
                let staged = try await LibraryStorage.shared.stage(url)
                stagedURL = staged
                try Task.checkCancellation()
                pdf = try await extractor.inspectPDF(staged)
                try Task.checkCancellation()
                preparing = false; processing = false
            } catch { await finishError(error) }
        }
    }
    func importPDF(_ pages: ClosedRange<Int>, library: LibraryController) {
        guard let pdf else { return }
        processing = true
        work = Task {
            do {
                let content = try await extractor.pdf(pdf.url, pages: pages, progress: reporter)
                try Task.checkCancellation()
                progress = .init(stage: "Organizing", detail: "Saving document…", completed: 1, total: 1)
                try await library.add(title: pdf.url.deletingPathExtension().lastPathComponent, kind: .pdf, content: content, source: pdf.url, thumbnail: pdf.thumbnail)
                await cleanup(); completed = true; processing = false
            } catch { await finishError(error) }
        }
    }
    func prepareEPUB(_ url: URL) {
        processing = true; preparing = true; title = url.lastPathComponent
        work = Task {
            do {
                let staged = try await LibraryStorage.shared.stage(url)
                stagedURL = staged
                try Task.checkCancellation()
                epub = try await epubService.inspect(staged)
                try Task.checkCancellation()
                preparing = false; processing = false
            } catch { await finishError(error) }
        }
    }
    func importEPUB(_ selected: Set<Int>, library: LibraryController) {
        guard let epub else { return }
        processing = true; title = epub.title
        work = Task {
            do {
                let content = try await epubService.extract(epub, selected: selected, progress: reporter)
                try Task.checkCancellation()
                progress = .init(stage: "Organizing", detail: "Saving document…", completed: 1, total: 1)
                try await library.add(title: epub.title, kind: .epub, content: content, source: epub.url, thumbnail: epub.cover)
                await cleanup(); completed = true; processing = false
            } catch { await finishError(error) }
        }
    }
    func importPhotos(_ items: [PhotosPickerItem], library: LibraryController) {
        guard !items.isEmpty else { return }
        processing = true; preparing = true; title = "Photos"
        work = Task {
            do {
                let directory = try makePagesFolder()
                var urls: [URL] = []
                for (index, item) in items.enumerated() {
                    try Task.checkCancellation()
                    progress = .init(stage: "Importing", detail: "Importing photo \(index + 1) of \(items.count)…", completed: index, total: items.count)
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw ReaderError.unsupportedImage }
                    let url = directory.appending(path: String(format: "%04d.image", index + 1))
                    try await extractor.writeImage(data, to: url)
                    urls.append(url)
                }
                try await processImages(urls, directory: directory, kind: .images, library: library)
            } catch { await finishError(error) }
        }
    }
    func importScan(_ scan: VNDocumentCameraScan, library: LibraryController) {
        guard scan.pageCount > 0 else { return }
        processing = true; preparing = true; title = "Scanned pages"
        work = Task {
            do {
                let directory = try makePagesFolder()
                var urls: [URL] = []
                for index in 0..<scan.pageCount {
                    try Task.checkCancellation()
                    progress = .init(stage: "Importing", detail: "Saving scan \(index + 1) of \(scan.pageCount)…", completed: index, total: scan.pageCount)
                    let url = directory.appending(path: String(format: "%04d.jpg", index + 1))
                    try await extractor.writeScan(scan.imageOfPage(at: index), to: url)
                    urls.append(url)
                }
                try await processImages(urls, directory: directory, kind: .scan, library: library)
            } catch { await finishError(error) }
        }
    }
    private func makePagesFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ReaderImport-\(UUID().uuidString)/Pages")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        stagedURL = folder
        return folder
    }
    private func processImages(_ urls: [URL], directory: URL, kind: SourceKind, library: LibraryController) async throws {
        preparing = false
        let (content, thumbnail) = try await extractor.images(urls, progress: reporter)
        try Task.checkCancellation()
        progress = .init(stage: "Organizing", detail: "Saving document…", completed: 1, total: 1)
        try await library.add(title: "\(kind == .scan ? "Scan" : "Photos") · \(Date.now.formatted(date: .abbreviated, time: .shortened))", kind: kind, content: content, source: directory, thumbnail: thumbnail)
        await cleanup(); completed = true; processing = false
    }
    var reporter: ProgressReporter { { [weak self] value in await self?.update(value) } }
    func update(_ value: ExtractionProgress) { progress = value }
    func cancel() { cancelling = true; work?.cancel() }
    func cleanup() async {
        if let stagedURL { await LibraryStorage.shared.discardStaged(stagedURL) }
        stagedURL = nil
    }
    func finishError(_ failure: Error) async {
        // Vision may report its own cancellation error instead of Swift CancellationError.
        let wasCancelled = cancelling || Task.isCancelled || failure is CancellationError
        await cleanup()
        if !wasCancelled { error = failure.localizedDescription }
        else { completed = true }
        processing = false; preparing = false; cancelling = false
    }
}
