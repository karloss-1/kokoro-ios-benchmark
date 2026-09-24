import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var library: LibraryController
    @Environment(\.scenePhase) private var phase
    var body: some View {
        TabView {
            Tab("Library", systemImage: "book.fill") { LibraryView(library: library) }
            Tab("Settings", systemImage: "gearshape") { SettingsView(settings: library.settings, speech: library.speech) }
        }
        .onChange(of: phase) { _, value in
            if value != .active { library.savePosition() }
            else { library.speech.refreshVoices() }
        }
        .alert("Unable to complete action", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button("OK", role: .cancel) { library.error = nil }
        } message: { Text(library.error ?? "") }
    }
}

struct LibraryView: View {
    @Bindable var library: LibraryController
    @State private var search = ""
    @State private var sort = "Last Opened"
    @State private var adding = false
    @State private var showingReader = false
    @State private var renameTarget: LibraryDocument?
    @State private var renameTitle = ""
    @State private var deleteTarget: LibraryDocument?
    @State private var export: TextExport?
    @State private var exporting = false
    @State private var exportName = "Document"
    var visible: [LibraryDocument] {
        library.documents.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }.sorted {
            switch sort {
            case "Title": $0.title.localizedStandardCompare($1.title) == .orderedAscending
            case "Date Added": $0.importedAt > $1.importedAt
            default: ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast)
            }
        }
    }
    var recent: LibraryDocument? { library.documents.filter { $0.lastOpenedAt != nil && $0.progress < 1 }.max { ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast) } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search your library…", text: $search).accessibilityIdentifier("librarySearch")
                    }.padding(14).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
                    if search.isEmpty, let recent {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("CONTINUE LISTENING").font(.caption.weight(.semibold)).tracking(0.7).foregroundStyle(ReaderStyle.green)
                            HStack(spacing: 14) {
                                Button { open(recent) } label: {
                                    HStack(spacing: 14) {
                                        DocumentThumbnail(document: recent)
                                        VStack(alignment: .leading, spacing: 7) {
                                            Text(recent.title).font(.headline).foregroundStyle(.primary)
                                            Text(recent.sectionTitle ?? recent.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                            ProgressView(value: recent.progress)
                                            Text("\(Int(recent.progress * 100))% complete").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }.buttonStyle(.plain)
                                Button { open(recent, play: true) } label: {
                                    Image(systemName: "play.fill").foregroundStyle(.white).frame(width: 46, height: 46).background(ReaderStyle.green, in: Circle())
                                }.accessibilityLabel("Resume \(recent.title)")
                            }
                        }.padding(18).background(ReaderStyle.paleGreen, in: RoundedRectangle(cornerRadius: 22))
                    }
                    HStack {
                        Text("My Library").font(.title2.bold())
                        Spacer()
                        Menu { Picker("Sort", selection: $sort) { ForEach(["Last Opened", "Date Added", "Title"], id: \.self) { Text($0) } } } label: {
                            HStack(spacing: 4) { Text(sort); Image(systemName: "chevron.down") }.font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if visible.isEmpty {
                        ContentUnavailableView(search.isEmpty ? "Your reading starts here" : "No matching documents", systemImage: "books.vertical", description: Text(search.isEmpty ? "Tap + to add a document or text." : "Try another title."))
                    }
                    LazyVStack(spacing: 12) {
                        ForEach(visible) { document in
                            ReaderCard {
                                HStack(alignment: .top, spacing: 13) {
                                    Button { open(document) } label: {
                                        HStack(alignment: .top, spacing: 13) {
                                            DocumentThumbnail(document: document)
                                            VStack(alignment: .leading, spacing: 7) {
                                                Text(document.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                                                Text(document.subtitle).font(.subheadline).foregroundStyle(.secondary)
                                                ProgressView(value: document.progress)
                                                Text("\(Int(document.progress * 100))% complete").font(.caption).foregroundStyle(.secondary)
                                                if let date = document.lastOpenedAt { Text("Opened \(date.formatted(.relative(presentation: .named)))").font(.caption2).foregroundStyle(.secondary) }
                                            }.frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }.buttonStyle(.plain)
                                    Menu {
                                        Button("Rename", systemImage: "pencil") { renameTitle = document.title; renameTarget = document }
                                        Button("Export Text…", systemImage: "square.and.arrow.up") { exportText(document) }
                                        Button("Delete", systemImage: "trash", role: .destructive) { deleteTarget = document }
                                    } label: { Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 28, height: 28) }.accessibilityLabel("Actions for \(document.title)")
                                }
                            }
                        }
                    }
                }.padding(20).frame(maxWidth: 850).frame(maxWidth: .infinity)
            }.background(ReaderStyle.background).navigationTitle("Library")
                .toolbar { ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Image(systemName: "plus").font(.title3.weight(.medium)).foregroundStyle(.white).frame(width: 38, height: 38).background(ReaderStyle.green, in: Circle()) }.accessibilityLabel("Add to Library").accessibilityIdentifier("addToLibrary")
                } }
                .sheet(isPresented: $adding) { AddLibraryView(library: library) }
                .navigationDestination(isPresented: $showingReader) {
                    if let document = library.opened, let content = library.content { ReaderView(library: library, document: document, content: content) }
                }
                .overlay { if library.isOpening { ProgressView("Opening document…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20)) } }
                .alert("Rename document", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
                    TextField("Title", text: $renameTitle)
                    Button("Save") { if let target = renameTarget { library.rename(target, to: renameTitle) }; renameTarget = nil }
                    Button("Cancel", role: .cancel) { renameTarget = nil }
                }
                .confirmationDialog("Delete this document and its saved files?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { if let target = deleteTarget { Task { await library.delete(target) } }; deleteTarget = nil }
                }
                .fileExporter(isPresented: $exporting, document: export, contentType: .plainText, defaultFilename: exportName) { result in
                    if case .failure(let error) = result { library.error = error.localizedDescription }
                }
        }
    }
    private func open(_ document: LibraryDocument, play: Bool = false) {
        Task { await library.open(document, play: play); if library.opened?.id == document.id { showingReader = true } }
    }
    private func exportText(_ document: LibraryDocument) {
        Task {
            do {
                let content = try await LibraryStorage.shared.load(document.id)
                export = TextExport(text: content.exportedText)
                exportName = document.title.replacingOccurrences(of: "/", with: "-")
                exporting = true
            } catch { library.error = error.localizedDescription }
        }
    }
}

struct TextExport: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? "" }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

struct AddTextView: View {
    let library: LibraryController
    var onSaved: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        Form {
            TextField("Title", text: $title).accessibilityIdentifier("textTitle")
            TextEditor(text: $text).frame(minHeight: 300).accessibilityLabel("Text to read").accessibilityIdentifier("textContent")
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Add Text").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") {
                        saving = true
                        Task {
                            do {
                                let content = try await LibraryStorage.shared.createText(text)
                                try await library.add(title: title, kind: .text, content: content)
                                dismiss()
                                onSaved?()
                            } catch { self.error = error.localizedDescription; saving = false }
                        }
                    }.disabled(saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("saveText")
                }
            }.interactiveDismissDisabled(saving)
    }
}
