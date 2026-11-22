import AppKit

umask(0o077)

if let flagIndex = CommandLine.arguments.firstIndex(of: "--import-pastenow") {
    let path = CommandLine.arguments.dropFirst(flagIndex + 1).first
    exit(CommandLineImport.run(path: path))
}

for (flag, name) in [("--show", AppEnvironment.showPanelNotification), ("--settings", AppEnvironment.showSettingsNotification)]
where CommandLine.arguments.contains(flag) {
    DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.accessory)
application.run()
