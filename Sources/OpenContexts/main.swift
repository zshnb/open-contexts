import AppKit

MainActor.assumeIsolated {
    if let index = CommandLine.arguments.firstIndex(where: { $0 == "--activation-self-check" || $0 == "--activation-repair-self-check" || $0 == "--activation-cancel-self-check" }),
       CommandLine.arguments.indices.contains(index + 1) {
        let appID = CommandLine.arguments[index + 1]
        let application = NSApplication.shared
        let simulateRestoration = CommandLine.arguments[index] == "--activation-repair-self-check"
        let simulateCancellation = CommandLine.arguments[index] == "--activation-cancel-self-check"
        Task { @MainActor in exit(await WindowService.activationSelfCheck(appID: appID, simulateRestoration: simulateRestoration, simulateCancellation: simulateCancellation) ? 0 : 1) }
        application.run()
    }
    if CommandLine.arguments.contains("--spaces-self-check") {
        _ = NSApplication.shared
        exit(WindowService.spacesSelfCheck() ? 0 : 1)
    }
    if CommandLine.arguments.contains("--ui-self-check") {
        exit(PanelSmokeCheck.run() ? 0 : 1)
    }

    if CommandLine.arguments.contains("--self-check") {
        exit(ShortcutController.selfCheck() && AppSettings.selfCheck() && LaunchAtLoginController.selfCheck()
             && L10n.selfCheck() ? 0 : 1)
    }

    if CommandLine.arguments.contains("--window-self-check") {
        exit(WindowService.selfCheck() ? 0 : 1)
    }

    let application = NSApplication.shared
    let delegate = AppController()
    application.delegate = delegate
    withExtendedLifetime(delegate) { application.run() }
}
