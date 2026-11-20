import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var iconChunks = Data()
func bigEndianBytes(_ number: Int) -> Data {
    var value = UInt32(number).bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let factor = CGFloat(pixels) / 1024
        context.cgContext.scaleBy(x: factor, y: factor)
        NSColor(red: 0.93, green: 0.95, blue: 0.89, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 220, yRadius: 220).fill()
        let green = NSColor(red: 0.23, green: 0.49, blue: 0.37, alpha: 1)
        green.setStroke()
        let sun = NSBezierPath(ovalIn: NSRect(x: 352, y: 352, width: 320, height: 320))
        sun.lineWidth = 44
        sun.stroke()
        for ray in 0..<8 {
            let angle = CGFloat(ray) * .pi / 4
            let line = NSBezierPath()
            line.lineWidth = 42
            line.lineCapStyle = .round
            line.move(to: NSPoint(x: 512 + cos(angle) * 255, y: 512 + sin(angle) * 255))
            line.line(to: NSPoint(x: 512 + cos(angle) * 320, y: 512 + sin(angle) * 320))
            line.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let png = bitmap.representation(using: .png, properties: [:])!
        try png.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
        let codes = [16: ["icp4", "ic11"], 32: ["icp5", "ic12"], 128: ["ic07", "ic13"],
                     256: ["ic08", "ic14"], 512: ["ic09", "ic10"]]
        iconChunks.append(Data(codes[size]![scale - 1].utf8))
        iconChunks.append(bigEndianBytes(png.count + 8))
        iconChunks.append(png)
    }
}
var icon = Data("icns".utf8)
icon.append(bigEndianBytes(iconChunks.count + 8))
icon.append(iconChunks)
try icon.write(to: output.deletingLastPathComponent().appendingPathComponent("AppIcon.icns"))
