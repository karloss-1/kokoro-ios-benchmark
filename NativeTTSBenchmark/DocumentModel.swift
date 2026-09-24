import Foundation
import NaturalLanguage
import SwiftData

enum SourceKind: String, Codable, CaseIterable, Sendable {
    case text = "Text", pdf = "PDF", epub = "EPUB", images = "Images", scan = "Scan"
    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .pdf: "doc.richtext"
        case .epub: "book.closed.fill"
        case .images: "photo.on.rectangle"
        case .scan: "document.viewfinder"
        }
    }
}

@Model final class LibraryDocument {
    @Attribute(.unique) var id: UUID
    var title: String
    var sourceType: String
    var sourceFilename: String?
    var contentFilename: String
    var thumbnailFilename: String?
    var importedAt: Date
    var lastOpenedAt: Date?
    var sentenceIndex: Int
    var progress: Double
    var sectionIndex: Int
    var paragraphIndex: Int
    var pageNumber: Int?
    var sectionTitle: String?
    var pageCount: Int?
    var sectionCount: Int
    var language: String?

    init(id: UUID, title: String, kind: SourceKind, sourceFilename: String?, thumbnailFilename: String?, content: ReadingDocument) {
        self.id = id
        self.title = title
        sourceType = kind.rawValue
        self.sourceFilename = sourceFilename
        contentFilename = "content.json"
        self.thumbnailFilename = thumbnailFilename
        importedAt = .now
        sentenceIndex = 0
        progress = 0
        sectionIndex = 0
        paragraphIndex = 0
        pageNumber = content.sections.first?.pageNumber
        sectionTitle = content.sections.first?.title
        pageCount = content.originalPageCount
        sectionCount = content.sections.count
        language = content.language
    }
    var kind: SourceKind { SourceKind(rawValue: sourceType) ?? .text }
    var subtitle: String {
        if let pageCount { return "\(sourceType) · \(pageCount) pages" }
        if kind == .epub { return "EPUB · \(sectionCount) sections" }
        return sourceType
    }
}

struct ReadingDocument: Codable, Sendable {
    var schemaVersion = 1
    var language: String?
    var originalPageCount: Int?
    var sections: [ReadingSection]

    var units: [ReadingUnit] {
        var result: [ReadingUnit] = []
        var offset = 0
        for (sectionIndex, section) in sections.enumerated() {
            for (paragraphIndex, paragraph) in section.paragraphs.enumerated() {
                for sentence in paragraph.sentences {
                    result.append(ReadingUnit(id: result.count, section: sectionIndex, paragraph: paragraphIndex,
                                              text: sentence, characterOffset: offset))
                    offset += sentence.count
                }
            }
        }
        return result
    }
    var exportedText: String {
        sections.map { section in
            var blocks: [String] = []
            if let title = section.title, !title.isEmpty { blocks.append(title) }
            if let page = section.pageNumber { blocks.append("[Page \(page)]") }
            blocks.append(contentsOf: section.paragraphs.map(\.text))
            return blocks.joined(separator: "\n\n")
        }.joined(separator: "\n\n")
    }
}
struct ReadingSection: Codable, Identifiable, Sendable {
    var id = UUID()
    var title: String?
    var pageNumber: Int?
    var paragraphs: [ReadingParagraph]
}
struct ReadingParagraph: Codable, Identifiable, Sendable {
    var id = UUID()
    var text: String
    var sentences: [String]
}
struct ReadingUnit: Identifiable, Sendable {
    var id: Int
    var section: Int
    var paragraph: Int
    var text: String
    var characterOffset: Int
}

enum DocumentNormalizer {
    static func section(text: String, title: String? = nil, page: Int? = nil) -> ReadingSection {
        // Normalize line endings only. Never rewrite spelling, hyphenation or OCR output.
        let text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let tokenizer = NLTokenizer(unit: .paragraph)
        tokenizer.string = text
        var paragraphs: [ReadingParagraph] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let paragraph = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !paragraph.isEmpty else { return true }
            let sentences = NLTokenizer(unit: .sentence)
            sentences.string = paragraph
            var pieces: [String] = []
            sentences.enumerateTokens(in: paragraph.startIndex..<paragraph.endIndex) { range, _ in
                let piece = String(paragraph[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !piece.isEmpty { pieces.append(piece) }
                return true
            }
            paragraphs.append(ReadingParagraph(text: paragraph, sentences: pieces.isEmpty ? [paragraph] : pieces))
            return true
        }
        return ReadingSection(title: title, pageNumber: page, paragraphs: paragraphs)
    }
    static func document(sections: [ReadingSection], originalPageCount: Int? = nil) throws -> ReadingDocument {
        guard sections.contains(where: { !$0.paragraphs.isEmpty }) else { throw ReaderError.noText }
        let sample = sections.lazy.flatMap(\.paragraphs).prefix(30).map(\.text).joined(separator: "\n")
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(sample.prefix(12000)))
        return ReadingDocument(language: recognizer.dominantLanguage?.rawValue, originalPageCount: originalPageCount, sections: sections)
    }
}

enum ReaderError: LocalizedError {
    case noText, missingFile, invalidPDF, lockedPDF, invalidRange, unsupportedImage, unsupportedEPUB, message(String)
    var errorDescription: String? {
        switch self {
        case .noText: "No readable text was found. Try clearer pages or add text manually."
        case .missingFile: "This document’s saved content is missing. Import the original again."
        case .invalidPDF: "This PDF could not be opened. It may be damaged or unsupported."
        case .lockedPDF: "This PDF is encrypted or does not permit text extraction. Import an unlocked copy."
        case .invalidRange: "Enter a valid page range within this PDF."
        case .unsupportedImage: "This image could not be decoded. Try a JPEG, PNG or HEIC image."
        case .unsupportedEPUB: "This EPUB is protected, damaged or unsupported. Only non-DRM EPUBs are supported."
        case .message(let message): message
        }
    }
}
