import AppKit
import Testing
@testable import Clipdeck

@Suite("Menu bar icon")
@MainActor
struct MenuBarIconTests {
    private let icon = StatusItemController.makeIcon()
    private let frontCard = CGPoint(x: 7, y: 5)
    private let backCardEdge = CGPoint(x: 17, y: 7)
    private let emptyCorner = CGPoint(x: 1, y: 13)

    @Test("should be a template image so macOS tints it for light and dark menu bars")
    func template() {
        #expect(icon.isTemplate)
        #expect(icon.size == NSSize(width: 18, height: 14))
    }

    @Test("should draw a solid front card over a faded back card like the app icon")
    func twoCards() {
        #expect(alpha(of: icon, at: frontCard) > 0.95)
        #expect(abs(alpha(of: icon, at: backCardEdge) - 0.4) < 0.05)
        #expect(alpha(of: icon, at: emptyCorner) == 0)
    }

    @Test("should start the saved animation with a single solid card")
    func animationStart() {
        let first = StatusItemController.makeIcon(progress: 0)
        #expect(first.isTemplate)
        #expect(alpha(of: first, at: frontCard) > 0.95)
        #expect(alpha(of: first, at: backCardEdge) == 0)
    }

    @Test("should end the saved animation on the resting icon")
    func animationEnd() {
        let last = StatusItemController.makeIcon(progress: 1)
        for point in [frontCard, backCardEdge, emptyCorner] {
            #expect(abs(alpha(of: last, at: point) - alpha(of: icon, at: point)) < 0.01)
        }
    }

    private func alpha(of image: NSImage, at point: CGPoint) -> CGFloat {
        let scale: CGFloat = 2
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * scale), pixelsHigh: Int(image.size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        let pixelY = Int((image.size.height - point.y) * scale)
        return rep.colorAt(x: Int(point.x * scale), y: pixelY)?.alphaComponent ?? -1
    }
}
