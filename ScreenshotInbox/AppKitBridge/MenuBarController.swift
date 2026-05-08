import AppKit
import Combine

@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private weak var appState: AppState?
    private var cancellable: AnyCancellable?

    init(appState: AppState) {
        self.appState = appState
        super.init()
        configureStatusItem()
        cancellable = appState.screenshotInboxStore.$items.sink { [weak self] _ in
            self?.refreshStatusItem()
        }
        refreshStatusItem()
    }

    private func configureStatusItem() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }
        guard let statusItem, let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Screenshot Inbox")
        button.imagePosition = .imageLeft
        statusItem.menu = makeMenu()
    }

    func refreshStatusItem() {
        guard let statusItem, let button = statusItem.button, let appState else { return }
        let count = appState.screenshotInboxStore.newUndismissedCount
        print("[Count] newUndismissedCount = \(count)")
        button.title = appState.screenshotInboxPreferences.menuBarBadgeEnabled && count > 0 ? " \(count)" : ""
        print("[MenuBar] badge updated = \(count)")
        statusItem.menu = makeMenu()
    }

    func removeStatusItem() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let count = appState?.screenshotInboxStore.newUndismissedCount ?? 0

        let title = NSMenuItem(title: "Screenshot Inbox", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let countItem = NSMenuItem(title: count == 1 ? "1 New Screenshot" : "\(count) New Screenshots", action: nil, keyEquivalent: "")
        countItem.isEnabled = false
        menu.addItem(countItem)
        menu.addItem(NSMenuItem(title: "Open Inbox", action: #selector(openInbox), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Show Floating Preview", action: #selector(showLatestScreenshot), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Screenshot Inbox", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items where item.action != nil {
            item.target = self
        }
        return menu
    }

    @objc private func openInbox() {
        print("[MenuBar] Open Inbox clicked")
        appState?.openScreenshotInboxWindow()
    }

    @objc private func showLatestScreenshot() {
        appState?.showLatestScreenshotPanel()
    }

    @objc private func openSettings() {
        print("[Settings] Settings clicked from menu bar")
        AppWindowRouter.shared.openSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
