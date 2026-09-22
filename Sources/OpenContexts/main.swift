import AppKit

MainActor.assumeIsolated {
    if CommandLine.arguments.contains("--ui-self-check") {
        exit(PanelSmokeCheck.run() ? 0 : 1)
    }

    if CommandLine.arguments.contains("--self-check") {
        exit(ShortcutController.selfCheck() && AppSettings.selfCheck() ? 0 : 1)
    }

    if CommandLine.arguments.contains("--window-self-check") {
        exit(WindowService.selfCheck() ? 0 : 1)
    }

    let application = NSApplication.shared
    let delegate = AppController()
    application.delegate = delegate
    withExtendedLifetime(delegate) { application.run() }
}
