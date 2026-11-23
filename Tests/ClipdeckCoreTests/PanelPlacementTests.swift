import CoreGraphics
import Testing
@testable import ClipdeckCore

@Suite("PanelPlacement")
struct PanelPlacementTests {
    private let size = CGSize(width: 364, height: 660)
    private let laptop = CGRect(x: 0, y: 0, width: 1470, height: 890)
    private let external = CGRect(x: 1470, y: 0, width: 2560, height: 1400)

    @Test("should open at the top right of the screen with the mouse when it was never moved")
    func defaultSpot() {
        let frame = PanelPlacement.frame(size: size, savedTopLeft: nil, screens: [laptop, external], mouseScreen: external)
        #expect(frame == CGRect(x: external.maxX - 364 - 10, y: 1400 - 660 - 10, width: 364, height: 660))
    }

    @Test("should shrink the panel to fit a short screen")
    func shortScreen() {
        let small = CGRect(x: 0, y: 0, width: 1024, height: 500)
        let frame = PanelPlacement.frame(size: size, savedTopLeft: nil, screens: [small], mouseScreen: small)
        #expect(frame.height == 480)
        #expect(frame.maxY == 490)
    }

    @Test("should open where it was dragged to")
    func savedSpot() {
        let frame = PanelPlacement.frame(size: size, savedTopLeft: CGPoint(x: 200, y: 850), screens: [laptop], mouseScreen: laptop)
        #expect(frame == CGRect(x: 200, y: 850 - 660, width: 364, height: 660))
    }

    @Test("should keep a saved spot fully on the screen")
    func clamped() {
        let frame = PanelPlacement.frame(size: size, savedTopLeft: CGPoint(x: 1400, y: 300), screens: [laptop], mouseScreen: laptop)
        #expect(frame.maxX == laptop.maxX)
        #expect(frame.minY == laptop.minY)
    }

    @Test("should open at the same spot on the screen with the mouse")
    func sameSpotOtherScreen() {
        let frame = PanelPlacement.frame(size: size, savedTopLeft: CGPoint(x: 553, y: 890), screens: [laptop, external], mouseScreen: external)
        #expect(frame == CGRect(x: 1470 + 1098, y: 1400 - 660, width: 364, height: 660))
    }

    @Test("should keep a panel dragged to a corner in that corner on a smaller screen")
    func cornerOnSmallerScreen() {
        let frame = PanelPlacement.frame(size: size, savedTopLeft: CGPoint(x: 1470, y: 660), screens: [laptop, external], mouseScreen: laptop)
        #expect(frame == CGRect(x: 0, y: 0, width: 364, height: 660))
    }

    @Test("should read a spot near the edge between two screens from the screen it is on")
    func spotNearScreenEdge() {
        let frame = PanelPlacement.frame(size: size, savedTopLeft: CGPoint(x: 1480, y: 880), screens: [laptop, external], mouseScreen: external)
        #expect(frame == CGRect(x: 1480, y: 880 - 660, width: 364, height: 660))
    }

    @Test("should use the screen that holds most of the panel")
    func screenWithMostOfPanel() {
        let frame = PanelPlacement.frame(size: size, savedTopLeft: CGPoint(x: 1460, y: 880), screens: [laptop, external], mouseScreen: external)
        #expect(frame == CGRect(x: 1470, y: 880 - 660, width: 364, height: 660))
    }

    @Test("should go back to the top right when the saved spot is on a screen that is gone")
    func missingScreen() {
        let frame = PanelPlacement.frame(size: size, savedTopLeft: CGPoint(x: 3000, y: 1200), screens: [laptop], mouseScreen: laptop)
        #expect(frame.maxX == laptop.maxX - 10)
        #expect(frame.maxY == laptop.maxY - 10)
    }
}
