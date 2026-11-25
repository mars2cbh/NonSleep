import AppKit

// Finder uses the 1x/2x TIFF representations at the appropriate display scale.
let size = NSSize(width: 640, height: 400)
let image = NSImage(size: size)
let green = NSColor(srgbRed: 0.23, green: 0.49, blue: 0.37, alpha: 1)
for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
        pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    NSColor(srgbRed: 0.96, green: 0.96, blue: 0.93, alpha: 1).setFill()
    NSRect(origin: .zero, size: size).fill()

    func text(_ value: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (value as NSString).draw(in: NSRect(x: 24, y: y, width: 592, height: size + 12), withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color, .paragraphStyle: paragraph
        ])
    }
    text("NonSleep", y: 320, size: 30, weight: .semibold, color: green)
    text("YOUR MAC, AWAKE.", y: 298, size: 11, weight: .medium, color: .gray)
    green.withAlphaComponent(0.55).setStroke()
    let arrow = NSBezierPath()
    arrow.lineWidth = 4
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 282, y: 210))
    arrow.line(to: NSPoint(x: 358, y: 210))
    arrow.move(to: NSPoint(x: 344, y: 224))
    arrow.line(to: NSPoint(x: 358, y: 210))
    arrow.line(to: NSPoint(x: 344, y: 196))
    arrow.stroke()
    text("Drag NonSleep into Applications to install.", y: 74, size: 14, weight: .medium,
         color: NSColor(srgbRed: 0.28, green: 0.30, blue: 0.28, alpha: 1))
    text("NonSleep을 Applications 폴더로 끌어 설치하세요.", y: 48, size: 12, weight: .regular, color: .gray)
    NSGraphicsContext.restoreGraphicsState()
    image.addRepresentation(bitmap)
}
try image.tiffRepresentation!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
