import CoreGraphics

public enum PanelPlacement {
    public static let margin: CGFloat = 10
    private static let screenTolerance: CGFloat = 50

    public static func frame(size: CGSize, savedTopLeft: CGPoint?, screens: [CGRect], mouseScreen: CGRect) -> CGRect {
        if let saved = savedTopLeft,
           let screen = screens.first(where: { $0.insetBy(dx: -screenTolerance, dy: -screenTolerance).containsInclusive(saved) }) {
            let height = fittedHeight(size.height, on: screen)
            let x = min(max(saved.x, screen.minX), screen.maxX - size.width)
            let top = min(max(saved.y, screen.minY + height), screen.maxY)
            return CGRect(x: x, y: top - height, width: size.width, height: height)
        }
        let height = fittedHeight(size.height, on: mouseScreen)
        return CGRect(
            x: mouseScreen.maxX - size.width - margin,
            y: mouseScreen.maxY - height - margin,
            width: size.width,
            height: height
        )
    }

    private static func fittedHeight(_ height: CGFloat, on screen: CGRect) -> CGFloat {
        min(height, screen.height - margin * 2)
    }
}

private extension CGRect {
    func containsInclusive(_ point: CGPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }
}
