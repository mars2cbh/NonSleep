import NonSleepCore
import AppKit

enum StatusAppearance: Int, CaseIterable {
    case idle = 0
    case awake = 1
    case lid = 2
    case awakeAndLid = 3
    case focus = 4
    case awakeAndFocus = 5
    case lidAndFocus = 6
    case all = 7

    init(awake: Bool, lid: Bool, focus: Bool) {
        self = Self(rawValue: (awake ? 1 : 0) | (lid ? 2 : 0) | (focus ? 4 : 0))!
    }

    var activeCount: Int { rawValue.nonzeroBitCount }
    var symbolName: String { self == .idle ? "cup.and.saucer" : "cup.and.saucer.fill" }

    var color: NSColor {
        let rgb: (CGFloat, CGFloat, CGFloat)
        switch self {
        case .idle: rgb = (0.56, 0.58, 0.62)
        case .awake: rgb = (0.13, 0.72, 0.40)
        case .lid: rgb = (0.23, 0.51, 0.96)
        case .focus: rgb = (0.66, 0.33, 0.97)
        case .awakeAndLid: rgb = (0.02, 0.72, 0.80)
        case .awakeAndFocus: rgb = (0.98, 0.45, 0.09)
        case .lidAndFocus: rgb = (0.93, 0.28, 0.60)
        case .all: rgb = (0.96, 0.75, 0.08)
        }
        return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
    }

    var featureDescription: String {
        var names: [String] = []
        if rawValue & 1 != 0 { names.append(L10n.tr("Keep Awake")) }
        if rawValue & 2 != 0 { names.append(L10n.tr("Stay Awake with Lid Closed")) }
        if rawValue & 4 != 0 { names.append(L10n.tr("Do Not Disturb (last request)")) }
        return names.isEmpty ? L10n.tr("All features off") : names.joined(separator: " + ")
    }

    @MainActor
    func makeStatusImage() -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: "NonSleep")?
            .withSymbolConfiguration(.init(pointSize: 18, weight: .semibold)) else { return nil }
        let tint = color
        // Draw at the display's scale so the larger icon stays sharp on Retina.
        let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            let scale = min(bounds.width / symbol.size.width, bounds.height / symbol.size.height)
            let size = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
            let rect = NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                              width: size.width, height: size.height)
            symbol.draw(in: rect)
            tint.setFill()
            bounds.fill(using: .sourceIn)
            context.endTransparencyLayer()
            context.restoreGState()
            return true
        }
        // Template images are recolored by macOS; retain the actual feature color.
        image.isTemplate = false
        return image
    }
}
