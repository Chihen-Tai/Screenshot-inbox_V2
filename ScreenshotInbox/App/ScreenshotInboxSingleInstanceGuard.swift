import AppKit
import Foundation

enum ScreenshotInboxSingleInstanceGuard {
    struct AppIdentity: Equatable {
        let processIdentifier: pid_t
        let bundleIdentifier: String?
        let executableURL: URL?

        var executableName: String {
            executableURL?.lastPathComponent ?? ""
        }

        var path: String {
            executableURL?.path ?? "unknown"
        }
    }

    enum Result: Equatable {
        case keepCurrent
        case terminateCurrent
    }

    struct Decision: Equatable {
        let result: Result
        let existingInstance: AppIdentity?
    }

    enum LaunchedApplicationAction: Equatable {
        case ignore
        case terminateLaunchedApplication
    }

    private static var duplicateLaunchObserver: NSObjectProtocol?

    @discardableResult
    @MainActor
    static func enforce() -> Decision {
        let current = currentIdentity()
        let running = NSWorkspace.shared.runningApplications.map(AppIdentity.init)
        let decision = evaluate(current: current, runningApplications: running)

        print("[Lifecycle] app launched path = \(current.path)")
        print("[Lifecycle] bundle id = \(current.bundleIdentifier ?? "nil")")
        print("[Lifecycle] detected existing instance = \(decision.existingInstance?.path ?? "none")")

        if let existing = decision.existingInstance,
           current.path.contains("/.build/"),
           existing.path.hasPrefix("/Applications/") {
            print("[Lifecycle] Another Screenshot Inbox instance is running from /Applications. Please quit it before using swift run.")
        }

        switch decision.result {
        case .keepCurrent:
            print("[Lifecycle] single instance guard result = keep current pid \(current.processIdentifier)")
        case .terminateCurrent:
            print("[Lifecycle] single instance guard result = keep existing pid \(decision.existingInstance?.processIdentifier ?? -1), terminate current pid \(current.processIdentifier)")
            if let runningApp = NSWorkspace.shared.runningApplications.first(where: {
                $0.processIdentifier == decision.existingInstance?.processIdentifier
            }) {
                runningApp.activate(options: [.activateAllWindows])
            }
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }

        return decision
    }

    @MainActor
    static func startDuplicateLaunchMonitor() {
        guard duplicateLaunchObserver == nil else { return }
        duplicateLaunchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            Task { @MainActor in
                guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                    return
                }
                let current = currentIdentity()
                let launched = AppIdentity(application: application)
                let action = actionForLaunchedApplication(current: current, launched: launched)

                guard action == .terminateLaunchedApplication else { return }

                print("[Lifecycle] detected existing instance = \(launched.path)")
                print("[Lifecycle] single instance guard result = keep current pid \(current.processIdentifier), terminate launched pid \(launched.processIdentifier)")
                if !application.terminate() {
                    print("[Lifecycle] duplicate terminate request failed pid \(launched.processIdentifier)")
                }
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    static func actionForLaunchedApplication(
        current: AppIdentity,
        launched: AppIdentity
    ) -> LaunchedApplicationAction {
        guard launched.processIdentifier != current.processIdentifier,
              isMatchingInstance(current, launched) else {
            return .ignore
        }
        return .terminateLaunchedApplication
    }

    static func evaluate(
        current: AppIdentity,
        runningApplications: [AppIdentity]
    ) -> Decision {
        let existing = runningApplications.first { candidate in
            candidate.processIdentifier != current.processIdentifier && isMatchingInstance(current, candidate)
        }
        return Decision(
            result: existing == nil ? .keepCurrent : .terminateCurrent,
            existingInstance: existing
        )
    }

    static func hasMatchingBundleIdentifier(_ current: AppIdentity, _ candidate: AppIdentity) -> Bool {
        guard let currentID = current.bundleIdentifier?.lowercased(),
              let candidateID = candidate.bundleIdentifier?.lowercased(),
              !currentID.isEmpty,
              !candidateID.isEmpty else {
            return false
        }
        return currentID == candidateID
    }

    private static func isMatchingInstance(_ current: AppIdentity, _ candidate: AppIdentity) -> Bool {
        if hasMatchingBundleIdentifier(current, candidate) {
            return true
        }
        return isScreenshotInboxExecutable(current.executableName)
            && isScreenshotInboxExecutable(candidate.executableName)
    }

    private static func isScreenshotInboxExecutable(_ name: String) -> Bool {
        name == "ScreenshotInbox"
    }

    private static func currentIdentity() -> AppIdentity {
        AppIdentity(
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            bundleIdentifier: effectiveBundleIdentifier(),
            executableURL: Bundle.main.executableURL
                ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "")
        )
    }

    private static func effectiveBundleIdentifier() -> String? {
        #if DEBUG
        let fallback = "com.screenshotinbox.debug"
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            return fallback
        }
        return bundleIdentifier.hasSuffix(".debug") ? bundleIdentifier : "\(bundleIdentifier).debug"
        #else
        return Bundle.main.bundleIdentifier
        #endif
    }
}

private extension ScreenshotInboxSingleInstanceGuard.AppIdentity {
    init(application: NSRunningApplication) {
        self.init(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            executableURL: application.executableURL
        )
    }
}
