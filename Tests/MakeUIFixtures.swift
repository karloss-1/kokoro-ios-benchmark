// Simulator QA fixtures only; never linked into the application.
import AppKit
import PDFKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let mixed = PDFDocument(url: folder.appendingPathComponent("mixed.pdf"))!
let cancellation = PDFDocument()
for index in 0..<60 {
    cancellation.insert(mixed.page(at: 1)!.copy() as! PDFPage, at: index)
}
guard cancellation.write(to: folder.appendingPathComponent("cancel.pdf")) else { fatalError("Cannot create cancellation fixture") }
for (name, marker) in [("photo-first.png", "FIRST PHOTO. La fisioterapia estudia el movimiento."), ("photo-second.png", "SECOND PHOTO. La anatomia describe el cuerpo humano.")] {
    let image = NSImage(size: NSSize(width: 1200, height: 800))
    image.lockFocus()
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1200, height: 800).fill()
    (marker as NSString).draw(in: NSRect(x: 80, y: 250, width: 1040, height: 400), withAttributes: [.font: NSFont.systemFont(ofSize: 56), .foregroundColor: NSColor.black])
    image.unlockFocus()
    let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    try png.write(to: folder.appendingPathComponent(name))
}
