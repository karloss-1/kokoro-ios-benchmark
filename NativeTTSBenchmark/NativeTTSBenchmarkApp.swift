import SwiftData
import SwiftUI

@main
struct NativeTTSBenchmarkApp: App {
    @State private var library: LibraryController?
    private let initializationError: String?
    init() {
        do {
            let configuration = ModelConfiguration(cloudKitDatabase: .none)
            let container = try ModelContainer(for: LibraryDocument.self, configurations: configuration)
            _library = State(initialValue: LibraryController(container: container))
            initializationError = nil
        } catch { initializationError = error.localizedDescription }
    }
    var body: some Scene {
        WindowGroup {
            if let library {
                ContentView(library: library)
                    .tint(ReaderStyle.green)
                    .preferredColorScheme(library.settings.colorScheme)
            } else {
                ContentUnavailableView("Library could not open", systemImage: "externaldrive.badge.exclamationmark", description: Text(initializationError ?? "Unknown storage error. Your files have not been removed."))
            }
        }
    }
}
