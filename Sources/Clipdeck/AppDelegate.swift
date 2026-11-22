import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install(target: self)
        launch(isRetry: false)
    }

    private func launch(isRetry: Bool) {
        do {
            let controller = try AppController()
            controller.start()
            self.controller = controller
        } catch {
            Log.app.error("Startup failed: \(String(describing: error), privacy: .public)")
            if !isRetry && askToStartFresh(after: error) && HistoryRecovery.moveAside(in: AppEnvironment.dataDirectory) {
                launch(isRetry: true)
            } else {
                NSApp.terminate(nil)
            }
        }
    }

    private func askToStartFresh(after error: Error) -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Clipdeck could not open its history"
        alert.informativeText = """
            \(error.localizedDescription)

            Start Fresh moves the old history file aside, without deleting it, and starts a new one.
            """
        alert.addButton(withTitle: "Start Fresh")
        alert.addButton(withTitle: "Quit")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.showPanel()
        return false
    }

    @objc func openSettings(_ sender: Any?) {
        controller?.showSettings()
    }
}

@MainActor
enum MainMenu {
    static func install(target: AppDelegate) {
        let main = NSMenu()
        main.addItem(submenu: appMenu(target: target))
        main.addItem(submenu: editMenu())
        main.addItem(submenu: windowMenu())
        NSApp.mainMenu = main
    }

    private static func appMenu(target: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "Clipdeck")
        let settings = menu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.openSettings(_:)), keyEquivalent: ",")
        settings.target = target
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Clipdeck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return menu
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}

enum HistoryRecovery {
    static func moveAside(in directory: URL) -> Bool {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let database = directory.appendingPathComponent("history.sqlite").path
        do {
            for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: database + suffix) {
                try FileManager.default.moveItem(atPath: database + suffix, toPath: database + ".broken-\(stamp)" + suffix)
            }
            return true
        } catch {
            Log.app.error("Moving the broken history aside failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }
}
