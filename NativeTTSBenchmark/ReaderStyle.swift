import SwiftUI

enum ReaderStyle {
    static let green = Color(red: 0.035, green: 0.46, blue: 0.28)
    static let paleGreen = green.opacity(0.09)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
}
struct ReaderCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(ReaderStyle.surface, in: RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.025), radius: 12, y: 5)
    }
}
struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 19)
            .foregroundStyle(.white).background(ReaderStyle.green.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 20))
    }
}
struct DocumentThumbnail: View {
    let document: LibraryDocument
    var width: CGFloat = 58
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { ZStack { ReaderStyle.paleGreen; Image(systemName: document.kind.symbol).font(.title).foregroundStyle(ReaderStyle.green) } }
        }
        .frame(width: width, height: width * 1.28).clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: document.id) {
            if let data = await LibraryStorage.shared.thumbnail(document.id) { image = UIImage(data: data) }
        }
        .accessibilityHidden(true)
    }
}
