import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import VisionKit

struct AddLibraryView: View {
    let library: LibraryController
    @Environment(\.dismiss) private var dismiss
    @State private var coordinator = ImportCoordinator()
    @State private var files = false
    @State private var fileType: UTType = .pdf
    @State private var textEditor = false
    @State private var photos = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var scanner = false
    var body: some View {
        NavigationStack {
            Group {
                if coordinator.processing { ProcessingView(coordinator: coordinator) }
                else if let epub = coordinator.epub { EPUBOptionsView(preview: epub) { coordinator.importEPUB($0, library: library) } }
                else if let pdf = coordinator.pdf { PDFOptionsView(preview: pdf) { coordinator.importPDF($0, library: library) } }
                else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Import content to read and listen.").foregroundStyle(.secondary).padding(.bottom, 12)
                            importOption("Scan pages", "Use your camera to take photos of documents, notes or books.", "camera.fill") {
                                if VNDocumentCameraViewController.isSupported { scanner = true }
                                else { coordinator.error = "Document scanning is not available on this device. Choose photos instead." }
                            }
                            importOption("Choose photos", "Import images from your library.", "photo.fill") { photos = true }
                            importOption("Import PDF", "Add a PDF from Files or other apps.", "doc.fill") { fileType = .pdf; files = true }
                            importOption("Import EPUB", "Add an EPUB file from Files or other apps.", "book.closed.fill") { fileType = .epub; files = true }
                            importOption("Add text", "Paste or type text to read and listen.", "text.alignleft") { textEditor = true }
                        }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
                    }.background(ReaderStyle.background)
                }
            }
            .navigationTitle(coordinator.processing ? "Processing Document" : coordinator.epub != nil ? "Import EPUB" : coordinator.pdf == nil ? "Add to Library" : "Import PDF")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { if !coordinator.processing { ToolbarItem(placement: .topBarTrailing) { Button("Close", systemImage: "xmark") { dismiss() } } } }
            .fileImporter(isPresented: $files, allowedContentTypes: [fileType]) { result in
                switch result { case .success(let url): if fileType == .pdf { coordinator.preparePDF(url) } else { coordinator.prepareEPUB(url) }; case .failure(let error): coordinator.error = error.localizedDescription }
            }
            .photosPicker(isPresented: $photos, selection: $selectedPhotos, selectionBehavior: .ordered, matching: .images)
            .onChange(of: selectedPhotos) { _, items in coordinator.importPhotos(items, library: library) }
            .fullScreenCover(isPresented: $scanner) {
                DocumentScanner(completed: { scan in scanner = false; coordinator.importScan(scan, library: library) }, cancelled: { scanner = false }, failed: { error in scanner = false; coordinator.error = error.localizedDescription }).ignoresSafeArea()
            }
            .sheet(isPresented: $textEditor) { NavigationStack { AddTextView(library: library, onSaved: { dismiss() }) } }
            .interactiveDismissDisabled(coordinator.processing)
            .onChange(of: coordinator.completed) { _, value in if value { dismiss() } }
            .alert("Import could not finish", isPresented: Binding(get: { coordinator.error != nil }, set: { if !$0 { coordinator.error = nil } })) {
                Button("OK") { coordinator.error = nil; coordinator.pdf = nil; coordinator.epub = nil }
            } message: { Text(coordinator.error ?? "") }
            .onDisappear { coordinator.work?.cancel(); Task { await coordinator.cleanup() } }
        }
    }
    private func importOption(_ title: String, _ detail: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ReaderCard {
                HStack(spacing: 16) {
                    Image(systemName: symbol).font(.title).foregroundStyle(ReaderStyle.green).frame(width: 60, height: 68).background(ReaderStyle.paleGreen, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline).foregroundStyle(.primary); Text(detail).font(.subheadline).foregroundStyle(.secondary) }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
            }
        }.buttonStyle(.plain)
    }
}
struct PDFOptionsView: View {
    let preview: PDFPreview
    let importPages: (ClosedRange<Int>) -> Void
    @State private var all = true
    @State private var from = "1"
    @State private var to = ""
    var range: ClosedRange<Int>? {
        if all { return 1...preview.pageCount }
        guard let lower = Int(from), let upper = Int(to), lower >= 1, upper <= preview.pageCount, lower <= upper else { return nil }
        return lower...upper
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Choose which pages to add to your library.").foregroundStyle(.secondary)
                SourcePreview(title: preview.url.lastPathComponent, detail: "\(preview.pageCount) pages · \(ByteCountFormatter.string(fromByteCount: preview.byteCount, countStyle: .file))", data: preview.thumbnail, symbol: "doc.richtext")
                Text("Pages").font(.title2.bold())
                Button { all = true } label: { option("All pages", "Import all \(preview.pageCount) pages", selected: all, symbol: "doc.text") }.buttonStyle(.plain)
                ReaderCard {
                    VStack(alignment: .leading, spacing: 20) {
                        Button { all = false } label: { HStack { Label("Page range", systemImage: "document").font(.headline); Spacer(); Image(systemName: !all ? "largecircle.fill.circle" : "circle").foregroundStyle(ReaderStyle.green) }.frame(minHeight: 44).contentShape(Rectangle()) }.buttonStyle(.plain)
                        HStack {
                            VStack(alignment: .leading) { Text("From").foregroundStyle(.secondary); TextField("1", text: $from).keyboardType(.numberPad).textFieldStyle(.roundedBorder) }
                            VStack(alignment: .leading) { Text("To").foregroundStyle(.secondary); TextField("\(preview.pageCount)", text: $to).keyboardType(.numberPad).textFieldStyle(.roundedBorder) }
                        }.disabled(all)
                        if !all && range == nil { Text("Choose pages from 1 to \(preview.pageCount), in ascending order.").font(.caption).foregroundStyle(.red) }
                    }
                }
            }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }.background(ReaderStyle.background)
            .safeAreaInset(edge: .bottom) { Button("Import") { if let range { importPages(range) } }.buttonStyle(PrimaryButton()).disabled(range == nil).padding(20).background(.regularMaterial) }
            .onAppear { to = String(preview.pageCount) }
    }
    private func option(_ title: String, _ detail: String, selected: Bool, symbol: String) -> some View {
        ReaderCard { HStack { Image(systemName: symbol).font(.title).foregroundStyle(ReaderStyle.green).padding(12).background(ReaderStyle.paleGreen, in: RoundedRectangle(cornerRadius: 12)); VStack(alignment: .leading) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(.secondary) }; Spacer(); Image(systemName: selected ? "largecircle.fill.circle" : "circle").font(.title2).foregroundStyle(ReaderStyle.green) } }
    }
}
struct SourcePreview: View {
    let title: String
    let detail: String
    let data: Data?
    let symbol: String
    var body: some View {
        ReaderCard {
            HStack(spacing: 16) {
                if let data, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit().frame(width: 70, height: 94).clipShape(RoundedRectangle(cornerRadius: 10)) }
                else { Image(systemName: symbol).font(.largeTitle).foregroundStyle(ReaderStyle.green).frame(width: 70, height: 94).background(ReaderStyle.paleGreen, in: RoundedRectangle(cornerRadius: 10)) }
                VStack(alignment: .leading, spacing: 7) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(.secondary) }
            }
        }
    }
}
struct ProcessingView: View {
    @Bindable var coordinator: ImportCoordinator
    var body: some View {
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            Text("Extracting text so you can read and listen.").foregroundStyle(.secondary)
            ReaderCard {
                VStack(alignment: .leading, spacing: 24) {
                    Label(coordinator.title, systemImage: "doc.text").font(.headline)
                    HStack {
                        ForEach(["Importing", "Extracting text", "Organizing"], id: \.self) { stage in
                            VStack(spacing: 8) {
                                Image(systemName: coordinator.progress.stage == stage ? "largecircle.fill.circle" : "circle").font(.title2).foregroundStyle(coordinator.progress.stage == stage ? ReaderStyle.green : .secondary)
                                Text(stage).font(.caption).multilineTextAlignment(.center)
                            }.frame(maxWidth: .infinity)
                        }
                    }
                    if coordinator.preparing { ProgressView() }
                    else { ProgressView(value: Double(coordinator.progress.completed), total: Double(max(1, coordinator.progress.total))) }
                    Text(coordinator.cancelling ? "Cancelling after the current operation…" : coordinator.progress.detail).font(.subheadline).foregroundStyle(.secondary)
                }
            }
          }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }.background(ReaderStyle.background)
        .safeAreaInset(edge: .bottom) {
            Button(coordinator.cancelling ? "Cancelling…" : "Cancel") { coordinator.cancel() }.font(.headline).frame(maxWidth: .infinity).padding(18).background(ReaderStyle.paleGreen, in: Capsule()).disabled(coordinator.cancelling)
                .padding(20).background(.regularMaterial)
        }
    }
}

struct EPUBOptionsView: View {
    let preview: EPUBPreview
    let importChapters: (Set<Int>) -> Void
    @State private var selected: Set<Int> = []
    var allSelected: Bool { selected.count == preview.chapters.count }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Text("Choose which chapters to add to your library.").foregroundStyle(.secondary)
                SourcePreview(title: preview.title, detail: "EPUB · \(preview.chapters.count) chapters / sections", data: preview.cover, symbol: "book.closed")
                if let note = preview.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                Text("Chapters").font(.title2.bold())
                ReaderCard {
                    Button {
                        selected = allSelected ? [] : Set(preview.chapters.map(\.id))
                    } label: { HStack { Label("All chapters", systemImage: "book").font(.headline); Spacer(); Image(systemName: allSelected ? "checkmark.circle.fill" : "circle") } }.buttonStyle(.plain)
                }
                ForEach(preview.chapters) { chapter in
                    Button {
                        var ids = [chapter.id]
                        for child in preview.chapters.dropFirst(chapter.id + 1) {
                            if child.depth <= chapter.depth { break }
                            ids.append(child.id)
                        }
                        if selected.contains(chapter.id) { selected.subtract(ids) } else { selected.formUnion(ids) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text").foregroundStyle(.secondary)
                            Text(chapter.title).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: selected.contains(chapter.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(ReaderStyle.green)
                        }.padding(16).padding(.leading, CGFloat(min(chapter.depth, 4)) * 12).background(ReaderStyle.surface, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain).accessibilityAddTraits(selected.contains(chapter.id) ? .isSelected : [])
                }
            }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }.background(ReaderStyle.background)
            .safeAreaInset(edge: .bottom) { Button("Import") { importChapters(selected) }.buttonStyle(PrimaryButton()).disabled(selected.isEmpty).padding(20).background(.regularMaterial) }
            .onAppear { selected = Set(preview.chapters.map(\.id)) }
    }
}
