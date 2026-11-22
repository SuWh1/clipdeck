import AppKit
import SwiftUI

struct WindowDragArea: NSViewRepresentable {
    let onDrag: () -> Void

    func makeNSView(context: Context) -> DragView {
        DragView(onDrag: onDrag)
    }

    func updateNSView(_ view: DragView, context: Context) {
        view.onDrag = onDrag
    }

    final class DragView: NSView {
        var onDrag: () -> Void

        init(onDrag: @escaping () -> Void) {
            self.onDrag = onDrag
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            onDrag()
            window?.performDrag(with: event)
        }
    }
}
