import Foundation
@preconcurrency import ReadiumShared
@preconcurrency import ReadiumStreamer
import UIKit

struct EPUBChapter: Identifiable, Sendable {
    let id: Int
    let title: String
    let spine: Int
    let fragment: String?
    let depth: Int
}
struct EPUBPreview: Sendable {
    let url: URL
    let title: String
    let cover: Data?
    let chapters: [EPUBChapter]
    let note: String?
}

/// Required by Readium's asset factory. Explicitly refuses every HTTP request,
/// including remote resources referenced by a locally imported EPUB.
private struct OfflineHTTPClient: HTTPClient {
    func stream(request: HTTPRequestConvertible, consume: @escaping (Data, Double?) -> HTTPResult<Void>) async -> HTTPResult<HTTPResponse> {
        .failure(.offline(nil))
    }
}

actor EPUBService {
    private func open(_ url: URL) async throws -> Publication {
        guard let file = FileURL(url: url) else { throw ReaderError.unsupportedEPUB }
        let retriever = AssetRetriever(httpClient: OfflineHTTPClient())
        let asset = try await retriever.retrieve(url: file).get()
        let publication = try await PublicationOpener(parser: EPUBParser()).open(asset: asset, allowUserInteraction: false).get()
        guard !publication.isRestricted, !publication.readingOrder.isEmpty else { throw ReaderError.unsupportedEPUB }
        return publication
    }
    func inspect(_ url: URL) async throws -> EPUBPreview {
        let publication = try await open(url)
        try Task.checkCancellation()
        let toc = try await publication.tableOfContents().get()
        var entries: [EPUBChapter] = []
        var ignored = false
        func flatten(_ links: [Link], depth: Int) {
            for link in links {
                if let spine = publication.readingOrder.firstIndex(where: { Self.path($0.href) == Self.path(link.href) }) {
                    entries.append(EPUBChapter(id: entries.count, title: link.title ?? "Section \(entries.count + 1)", spine: spine, fragment: URLComponents(string: link.href)?.fragment, depth: depth))
                } else { ignored = true }
                flatten(link.children, depth: depth + 1)
            }
        }
        flatten(toc, depth: 0)
        let missingTOC = entries.isEmpty
        if missingTOC {
            entries = publication.readingOrder.enumerated().map { index, link in
                EPUBChapter(id: index, title: link.title ?? "Section \(index + 1)", spine: index, fragment: nil, depth: 0)
            }
        }
        let image = try? await publication.coverFitting(maxSize: CGSize(width: 300, height: 400)).get()
        return EPUBPreview(url: url, title: publication.metadata.title ?? url.deletingPathExtension().lastPathComponent,
                           cover: image?.jpegData(compressionQuality: 0.8), chapters: entries,
                           note: missingTOC ? "No usable table of contents. Showing sections in reading order." : ignored ? "Some table of contents links are outside the reading order and cannot be selected." : nil)
    }
    func extract(_ preview: EPUBPreview, selected: Set<Int>, progress: ProgressReporter) async throws -> ReadingDocument {
        guard !selected.isEmpty else { throw ReaderError.noText }
        let publication = try await open(preview.url)
        let all = selected.count == preview.chapters.count
        var output: [ReadingSection] = []
        var currentChapter: EPUBChapter?
        var currentParagraphs: [ReadingParagraph] = []
        func flush() {
            if !currentParagraphs.isEmpty {
                output.append(ReadingSection(title: currentChapter?.title, paragraphs: currentParagraphs))
                currentParagraphs = []
            }
        }
        for (spine, link) in publication.readingOrder.enumerated() {
            try Task.checkCancellation()
            await progress(.init(stage: "Extracting text", detail: "Reading EPUB section \(spine + 1) of \(publication.readingOrder.count)…", completed: spine, total: publication.readingOrder.count))
            guard let resource = publication.get(link), let href = AnyURL(string: link.href), (link.mediaType ?? .xhtml).isHTML else {
                if all { continue }
                throw ReaderError.message("This EPUB contains a non-text section that cannot be selected. Try importing all chapters.")
            }
            let locator = Locator(href: href, mediaType: link.mediaType ?? .xhtml)
            let iterator = HTMLResourceContentIterator(resource: resource, totalProgressionRange: { nil }, locator: locator)
            struct Element { let text: String?; let locator: Locator }
            var elements: [Element] = []
            while let element = try await iterator.next() {
                try Task.checkCancellation()
                elements.append(Element(text: (element as? TextualContentElement)?.text, locator: element.locator))
            }
            var boundaries: [(Int, EPUBChapter)] = []
            for chapter in preview.chapters where chapter.spine == spine {
                guard let fragment = chapter.fragment, !fragment.isEmpty else { boundaries.append((0, chapter)); continue }
                var start = locator
                let escaped = fragment.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                start.locations.cssSelector = "[id=\"\(escaped)\"]"
                let atAnchor = HTMLResourceContentIterator(resource: resource, totalProgressionRange: { nil }, locator: start)
                if let first = try await atAnchor.next(),
                   let position = elements.firstIndex(where: { $0.locator == first.locator }),
                   position > 0 || (first.locator.locations.cssSelector ?? "").contains("#" + fragment) {
                    boundaries.append((position, chapter))
                } else if !all {
                    throw ReaderError.message("The chapter boundary ‘\(chapter.title)’ could not be resolved safely. Import All chapters to retain the full text.")
                }
            }
            boundaries.sort { $0.0 == $1.0 ? $0.1.id < $1.1.id : $0.0 < $1.0 }
            var nextBoundary = 0
            for (elementIndex, element) in elements.enumerated() {
                while nextBoundary < boundaries.count && boundaries[nextBoundary].0 <= elementIndex {
                    flush(); currentChapter = boundaries[nextBoundary].1; nextBoundary += 1
                }
                guard all || currentChapter.map({ selected.contains($0.id) }) == true, let text = element.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                currentParagraphs.append(contentsOf: DocumentNormalizer.section(text: text).paragraphs)
            }
        }
        flush()
        try Task.checkCancellation()
        return try DocumentNormalizer.document(sections: output)
    }
    private static func path(_ href: String) -> String {
        (URLComponents(string: href)?.percentEncodedPath ?? href.components(separatedBy: "#")[0]).removingPercentEncoding ?? href
    }
}
