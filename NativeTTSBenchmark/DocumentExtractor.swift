import Foundation
import ImageIO
import PDFKit
import UIKit
import Vision

struct PDFPreview: Sendable {
    let url: URL
    let pageCount: Int
    let byteCount: Int64
    let thumbnail: Data?
}
struct ExtractionProgress: Sendable {
    var stage: String
    var detail: String
    var completed: Int
    var total: Int
}
typealias ProgressReporter = @Sendable (ExtractionProgress) async -> Void

/// PDFKit objects never leave this actor. At most one rendered page is kept for OCR.
actor DocumentExtractor {
    func inspectPDF(_ url: URL) throws -> PDFPreview {
        guard let pdf = PDFDocument(url: url), pdf.pageCount > 0 else { throw ReaderError.invalidPDF }
        guard !pdf.isLocked, pdf.allowsCopying else { throw ReaderError.lockedPDF }
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let thumbnail = pdf.page(at: 0)?.thumbnail(of: CGSize(width: 240, height: 320), for: .mediaBox).jpegData(compressionQuality: 0.8)
        return PDFPreview(url: url, pageCount: pdf.pageCount, byteCount: Int64(bytes), thumbnail: thumbnail)
    }
    func pdf(_ url: URL, pages: ClosedRange<Int>, progress: ProgressReporter) async throws -> ReadingDocument {
        guard let pdf = PDFDocument(url: url), pdf.pageCount > 0 else { throw ReaderError.invalidPDF }
        guard !pdf.isLocked, pdf.allowsCopying else { throw ReaderError.lockedPDF }
        guard pages.lowerBound >= 1, pages.upperBound <= pdf.pageCount else { throw ReaderError.invalidRange }
        var sections: [ReadingSection] = []
        for number in pages {
            try Task.checkCancellation()
            guard let page = pdf.page(at: number - 1) else { throw ReaderError.invalidPDF }
            var text = page.string ?? ""
            if Self.hasUsableText(text) {
                await progress(.init(stage: "Extracting text", detail: "Extracting text from page \(number) of \(pdf.pageCount)…", completed: number - pages.lowerBound, total: pages.count))
            } else {
                await progress(.init(stage: "Extracting text", detail: "Recognizing text on page \(number) of \(pdf.pageCount) (OCR)…", completed: number - pages.lowerBound, total: pages.count))
                let bounds = page.bounds(for: .mediaBox)
                guard bounds.width > 0, bounds.height > 0 else { throw ReaderError.invalidPDF }
                let scale = min(2400 / max(bounds.width, bounds.height), 3)
                let image = autoreleasepool { page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox) }
                guard let cg = image.cgImage else { throw ReaderError.unsupportedImage }
                let recognized = try await recognize(cg)
                if !recognized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { text = recognized }
            }
            try Task.checkCancellation()
            sections.append(DocumentNormalizer.section(text: text, page: number))
            await progress(.init(stage: "Extracting text", detail: "Processed page \(number) of \(pdf.pageCount)", completed: number - pages.lowerBound + 1, total: pages.count))
        }
        return try DocumentNormalizer.document(sections: sections, originalPageCount: pdf.pageCount)
    }
    static func hasUsableText(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        let replacements = text.filter { $0 == "\u{FFFD}" }.count
        return letters >= 16 && replacements * 5 < max(1, text.count)
    }
    func images(_ urls: [URL], progress: ProgressReporter) async throws -> (ReadingDocument, Data?) {
        var sections: [ReadingSection] = []
        var cover: Data?
        for (index, url) in urls.enumerated() {
            try Task.checkCancellation()
            await progress(.init(stage: "Extracting text", detail: "Recognizing page \(index + 1) of \(urls.count) (OCR)…", completed: index, total: urls.count))
            // ImageIO downsampling applies EXIF orientation without retaining the full-resolution image.
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2400
                  ] as CFDictionary) else { throw ReaderError.unsupportedImage }
            if index == 0, let small = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 360
            ] as CFDictionary) { cover = UIImage(cgImage: small).jpegData(compressionQuality: 0.8) }
            let text = try await recognize(image)
            try Task.checkCancellation()
            sections.append(DocumentNormalizer.section(text: text, page: index + 1))
        }
        return (try DocumentNormalizer.document(sections: sections, originalPageCount: urls.count), cover)
    }
    private func recognize(_ image: CGImage) async throws -> String {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.automaticallyDetectLanguage = true
        request.textRecognitionOptions.useLanguageCorrection = false
        let documents = try await request.perform(on: image)
        try Task.checkCancellation()
        // Complete transcript retains table/list text too; never filter those elements out.
        return documents.map { $0.document.text.transcript }.joined(separator: "\n\n")
    }
    func writeImage(_ data: Data, to url: URL) throws { try data.write(to: url, options: .atomic) }
    func writeScan(_ image: UIImage, to url: URL) throws {
        guard let data = image.jpegData(compressionQuality: 0.92) else { throw ReaderError.unsupportedImage }
        try data.write(to: url, options: .atomic)
    }
}
