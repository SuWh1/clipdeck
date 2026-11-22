import ClipdeckCore
import Observation
import SwiftUI

enum PanelPage {
    case history, settings
}

@Observable
@MainActor
final class PanelRouter {
    var page = PanelPage.history
}

struct PanelActions {
    let paste: (ClipItem, PasteMode) -> Void
    let openSettings: () -> Void
    let showHistory: () -> Void
    let panelMoved: () -> Void
    let runDetached: (() -> Void) -> Void
}

struct PanelRootView: View {
    let history: HistoryModel
    let settings: SettingsModel
    let router: PanelRouter
    let actions: PanelActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch router.page {
            case .history:
                HistoryView(model: history, actions: actions)
                    .transition(transition(from: .leading))
            case .settings:
                SettingsPage(settings: settings, actions: actions)
                    .transition(transition(from: .trailing))
            }
        }
        .animation(.easeOut(duration: 0.2), value: router.page)
        .background(WindowDragArea(onDrag: actions.panelMoved))
    }

    private func transition(from edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }
}
