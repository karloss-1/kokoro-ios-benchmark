import AVFoundation

import Foundation
import SwiftData
import UIKit
import PDFKit

@main struct IntegrationChecks {
    @MainActor static func main() async {
        do { try await run(); print("INTEGRATION CHECKS PASSED"); exit(0) }
        catch { print("INTEGRATION CHECKS FAILED: \(error)"); exit(1) }
    }
    static func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
        guard value() else { throw ReaderError.message("Assertion: " + message) }
        print("PASS: \(message)")
    }
    @MainActor static func run() async throws {
        let work = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let text = "La articulación glenohumeral permite el movimiento. La apófisis coracoides es una referencia anatómica.\n\nEl sistema musculoesquelético sostiene el cuerpo. La fisioterapia estudia la contracción muscular."
        let content = try DocumentNormalizer.document(sections: [DocumentNormalizer.section(text: text)])
        try check(content.sections.count == 1 && content.originalPageCount == nil, "text has no artificial pages")
        try check(content.sections[0].paragraphs.count == 2 && content.units.count == 4, "Spanish sentence / paragraph boundaries")
        try check(content.exportedText == text, "export preserves the Reader's normalized text")
        try check(content.language == "es", "automatic Spanish language detection")
        do { _ = try DocumentNormalizer.document(sections: [DocumentNormalizer.section(text: "   \n")]); throw ReaderError.message("Empty content accepted") } catch ReaderError.noText { print("PASS: empty text rejected") }
        let files = LibraryStorage(root: work.appending(path: "files"))
        let id = UUID()
        _ = try await files.save(id: id, content: content)
        let loaded = try await files.load(id)
        try check(loaded.exportedText == text && loaded.units.count == 4, "filesystem JSON round trip")
        let configuration = ModelConfiguration(url: work.appending(path: "checks.store"), cloudKitDatabase: .none)
        do {
            let container = try ModelContainer(for: LibraryDocument.self, configurations: configuration)
            let record = LibraryDocument(id: id, title: "Anatomía", kind: .text, sourceFilename: nil, thumbnailFilename: nil, content: content)
            container.mainContext.insert(record)
            record.sentenceIndex = 2; record.progress = 0.51; record.paragraphIndex = 1
            try container.mainContext.save()
        }
        let reopened = try ModelContainer(for: LibraryDocument.self, configurations: configuration)
        let records = try reopened.mainContext.fetch(FetchDescriptor<LibraryDocument>())
        try check(records.count == 1 && records[0].sentenceIndex == 2 && records[0].paragraphIndex == 1, "SwiftData restores sentence and paragraph position")
        let speech = SpeechEngine()
        speech.load(id: id, title: "Anatomía", content: content, position: 2, completed: false)
        try check(speech.index == 2 && speech.progress > 0, "engine restores deterministic semantic progress")
        speech.sentence(-1); try check(speech.index == 1, "previous sentence")
        speech.paragraph(1); try check(speech.index == 2, "next paragraph")
        speech.paragraph(-1); try check(speech.index == 0, "previous paragraph")
        speech.seek(progress: 1); try check(speech.index == 3, "100% seek resolves to last valid sentence")
        speech.seek(to: -100); try check(speech.index == 0, "out-of-range seek is clamped")
        speech.speechSynthesizer(AVSpeechSynthesizer(), didFinish: AVSpeechUtterance(string: "obsolete"))
        await Task.yield()
        try check(speech.index == 0, "obsolete utterance callback does not advance playback")
        speech.load(id: id, title: "Finished", content: content, position: 3, completed: true)
        speech.stop()
        try check(speech.progress == 1, "Stop preserves completed document progress")
        speech.configure(voiceID: "", rate: 1.25)
        try check(speech.progress == 1, "rate changes preserve completed document progress")
        let suite = "ReaderChecks-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = ReaderSettings(defaults: defaults)
        settings.rate = 1.5; settings.appearance = "Dark"; settings.voiceID = "missing-system-voice"
        let restored = ReaderSettings(defaults: defaults)
        try check(restored.rate == 1.5 && restored.appearance == "Dark" && restored.voiceID == "missing-system-voice", "settings persist")
        defaults.removePersistentDomain(forName: suite)
        let extractor = DocumentExtractor()
        let pdfURL = work.appending(path: "embedded.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        try renderer.pdfData { context in
            for page in 1...3 {
                context.beginPage()
                ("Embedded page \(page). La fisioterapia estudia el movimiento y la contracción muscular." as NSString).draw(in: CGRect(x: 40, y: 50, width: 520, height: 400), withAttributes: [.font: UIFont.systemFont(ofSize: 22)])
            }
        }.write(to: pdfURL)
        let preview = try await extractor.inspectPDF(pdfURL)
        try check(preview.pageCount == 3 && preview.thumbnail != nil, "PDF metadata and thumbnail")
        let pdf = try await extractor.pdf(pdfURL, pages: 2...3, progress: { _ in })
        try check(pdf.sections.map(\.pageNumber) == [2, 3] && pdf.originalPageCount == 3, "selected PDF page numbers remain original")
        try check(pdf.exportedText.contains("[Page 2]") && !pdf.exportedText.contains("Embedded page 1"), "PDF export preserves only selected pages")
        do { _ = try await extractor.pdf(pdfURL, pages: 1...9, progress: { _ in }); throw ReaderError.message("Invalid PDF range accepted") } catch ReaderError.invalidRange { print("PASS: invalid page range rejected") }
        let corruptPDF = work.appending(path: "corrupt.pdf")
        try Data("not a PDF".utf8).write(to: corruptPDF)
        do { _ = try await extractor.inspectPDF(corruptPDF); throw ReaderError.message("Corrupt PDF accepted") } catch ReaderError.invalidPDF { print("PASS: corrupt PDF rejected") }
        let cancelled = Task { try await extractor.pdf(pdfURL, pages: 1...3, progress: { _ in }) }
        cancelled.cancel()
        do { _ = try await cancelled.value; throw ReaderError.message("Cancelled PDF completed") } catch is CancellationError { print("PASS: PDF cancellation propagates") }
        let epubService = EPUBService()
        let epubPreview = try await epubService.inspect(work.appending(path: "chapters.epub"))
        try check(epubPreview.chapters.count == 3 && epubPreview.chapters.map(\.title) == ["One", "Two", "Three"], "Readium parses real EPUB TOC")
        let selected = try await epubService.extract(epubPreview, selected: [0, 2], progress: { _ in })
        try check(selected.exportedText.contains("FIRST") && selected.exportedText.contains("THIRD") && !selected.exportedText.contains("SECOND"), "noncontiguous EPUB chapters including shared XHTML anchors")
        try check(selected.originalPageCount == nil && selected.sections.allSatisfy { $0.pageNumber == nil }, "EPUB has no artificial pages")
        let all = try await epubService.extract(epubPreview, selected: Set(epubPreview.chapters.map(\.id)), progress: { _ in })
        try check(all.exportedText.contains("FIRST") && all.exportedText.contains("SECOND") && all.exportedText.contains("THIRD"), "all EPUB chapters extracted")
        let missingTOC = try await epubService.inspect(work.appending(path: "no-toc.epub"))
        try check(missingTOC.note != nil && missingTOC.chapters.count == 2, "missing EPUB TOC uses explicitly labeled reading order")
        // OCR and mixed PDF are required checks: any failure must fail this executable.
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 900)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1200, height: 900))
            ("La fisioterapia estudia el movimiento.\nEl sistema muscular sostiene el cuerpo." as NSString).draw(in: CGRect(x: 80, y: 150, width: 1000, height: 500), withAttributes: [.font: UIFont.systemFont(ofSize: 48), .foregroundColor: UIColor.black])
        }
        let imageURL = work.appending(path: "ocr.png")
        try image.pngData()!.write(to: imageURL)
        do {
            let (ocr, _) = try await extractor.images([imageURL], progress: { _ in })
            try check(ocr.exportedText.localizedCaseInsensitiveContains("fisioterapia"), "Vision document OCR on real image fixture")
            let mixedURL = work.appending(path: "mixed.pdf")
            // A renderer reused after pdfData produced an empty second PDF on SDK 27.
            let mixedRenderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
            let mixedData = mixedRenderer.pdfData { context in
                context.beginPage()
                ("Embedded layer about anatomy and movement." as NSString).draw(at: CGPoint(x: 40, y: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
                context.beginPage(); image.draw(in: CGRect(x: 0, y: 0, width: 612, height: 459))
            }
            try check(!mixedData.isEmpty && PDFDocument(data: mixedData)?.pageCount == 2, "mixed fixture contains two valid PDF pages")
            try check(PDFDocument(data: mixedData)?.page(at: 1)?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false, "mixed fixture second page has no embedded text")
            try mixedData.write(to: mixedURL)
            let mixed = try await extractor.pdf(mixedURL, pages: 1...2, progress: { _ in })
            try check(mixed.exportedText.contains("Embedded layer") && mixed.exportedText.localizedCaseInsensitiveContains("fisioterapia"), "mixed PDF uses text layer plus OCR")
        }
        let corruptImage = work.appending(path: "corrupt.png")
        try Data("not an image".utf8).write(to: corruptImage)
        do { _ = try await extractor.images([corruptImage], progress: { _ in }); throw ReaderError.message("Corrupt image accepted") } catch ReaderError.unsupportedImage { print("PASS: corrupt image rejected") }
        let corruptEPUB = work.appending(path: "corrupt.epub")
        try Data("not an EPUB".utf8).write(to: corruptEPUB)
        var rejectedEPUB = false
        do { _ = try await epubService.inspect(corruptEPUB) } catch { rejectedEPUB = true }
        try check(rejectedEPUB, "corrupt EPUB rejected")
        let noTOCContent = try await epubService.extract(missingTOC, selected: Set(missingTOC.chapters.map(\.id)), progress: { _ in })
        try check(noTOCContent.exportedText.contains("FIRST") && noTOCContent.exportedText.contains("THIRD"), "EPUB without TOC exports reading-order content")
        let imagePages = try await extractor.images([imageURL, imageURL], progress: { _ in }).0
        try check(imagePages.sections.map(\.pageNumber) == [1, 2] && imagePages.exportedText.contains("[Page 2]"), "multiple image pages preserve ordering and page markers")
        try await files.remove(id)
        do { _ = try await files.load(id); throw ReaderError.message("Deleted file remains") } catch ReaderError.missingFile { print("PASS: deletion removes managed content") }
        if CommandLine.arguments.count > 2 {
            // Optional simulator-only fixture seed; never used by the shipped app.
            let appData = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
            let support = appData.appending(path: "Library/Application Support")
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            let appStore = LibraryStorage(root: support.appending(path: "ReaderLibrary"))
            let model = try ModelContainer(for: LibraryDocument.self, configurations: ModelConfiguration(url: support.appending(path: "default.store"), cloudKitDatabase: .none))
            let newID = UUID()
            _ = try await appStore.save(id: newID, content: content)
            let row = LibraryDocument(id: newID, title: "Anatomía funcional — prueba", kind: .text, sourceFilename: nil, thumbnailFilename: nil, content: content)
            row.lastOpenedAt = .now; row.sentenceIndex = 2; row.progress = 0.51
            model.mainContext.insert(row); try model.mainContext.save()
            print("SEEDED SIMULATOR LIBRARY")
        }
    }
}
