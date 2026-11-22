import AppKit
import Testing
@testable import Clipdeck

@Suite("Menu bar icon")
@MainActor
struct MenuBarIconTests {
    private let icon = StatusItemController.makeIcon()

    @Test("should be a template image so macOS tints it for light and dark menu bars")
    func template() {
        #expect(icon.isTemplate)
        #expect(icon.size == NSSize(width: 18, height: 14))
    }

    @Test("should draw a solid front card over a faded back card like the app icon")
    func twoCards() {
        #expect(alpha(at: CGPoint(x: 7, y: 5)) > 0.95)
        #expect(abs(alpha(at: CGPoint(x: 17, y: 7)) - 0.4) < 0.05)
        #expect(alpha(at: CGPoint(x: 1, y: 13)) == 0)
    }

    private func alpha(at point: CGPoint) -> CGFloat {
        let scale: CGFloat = 2
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(icon.size.width * scale), pixelsHigh: Int(icon.size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = icon.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(origin: .zero, size: icon.size))
        NSGraphicsContext.restoreGraphicsState()
        let pixelY = Int((icon.size.height - point.y) * scale)
        return rep.colorAt(x: Int(point.x * scale), y: pixelY)?.alphaComponent ?? -1
    }
}
