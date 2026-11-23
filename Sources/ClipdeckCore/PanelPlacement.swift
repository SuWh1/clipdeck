import CoreGraphics

public enum PanelPlacement {
    public static let margin: CGFloat = 10

    public static func frame(size: CGSize, savedTopLeft: CGPoint?, screens: [CGRect], mouseScreen: CGRect) -> CGRect {
        let height = fittedHeight(size.height, on: mouseScreen)
        guard let saved = savedTopLeft, let screen = screen(holdingPanelAt: saved, size: size, in: screens) else {
            return CGRect(
                x: mouseScreen.maxX - size.width - margin,
                y: mouseScreen.maxY - height - margin,
                width: size.width,
                height: height
            )
        }
        let left = scaled(saved.x - screen.minX, from: screen.width - size.width, to: mouseScreen.width - size.width)
        let fromTop = scaled(
            screen.maxY - saved.y,
            from: screen.height - fittedHeight(size.height, on: screen),
            to: mouseScreen.height - height
        )
        return CGRect(x: mouseScreen.minX + left, y: mouseScreen.maxY - fromTop - height, width: size.width, height: height)
    }

    private static func screen(holdingPanelAt topLeft: CGPoint, size: CGSize, in screens: [CGRect]) -> CGRect? {
        let panel = CGRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
        let overlap = { (screen: CGRect) in screen.intersection(panel).width * screen.intersection(panel).height }
        guard let best = screens.max(by: { overlap($0) < overlap($1) }), overlap(best) > 0 else { return nil }
        return best
    }

    private static func scaled(_ offset: CGFloat, from space: CGFloat, to target: CGFloat) -> CGFloat {
        space > 0 ? min(max(offset, 0), space) * target / space : 0
    }

    private static func fittedHeight(_ height: CGFloat, on screen: CGRect) -> CGFloat {
        min(height, screen.height - margin * 2)
    }
}
