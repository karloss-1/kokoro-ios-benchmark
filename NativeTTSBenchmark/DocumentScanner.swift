import SwiftUI
import VisionKit

struct DocumentScanner: UIViewControllerRepresentable {
    let completed: (VNDocumentCameraScan) -> Void
    let cancelled: () -> Void
    let failed: (Error) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    @MainActor final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        init(parent: DocumentScanner) { self.parent = parent }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) { parent.completed(scan) }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { parent.cancelled() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { parent.failed(error) }
    }
}
