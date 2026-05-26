import AppKit
import Combine
import ServiceManagement
import SwiftUI

final class MenuBarController: NSObject, NSMenuDelegate, NSWindowDelegate {
    private let appState: AppState
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var window: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            let icon = NSImage(named: "MenuBarIcon")
            icon?.isTemplate = true
            icon?.size = NSSize(width: 18, height: 18)
            icon?.accessibilityDescription = "Inkognito"
            button.image = icon
            button.toolTip = "Inkognito — your printer's secret identity"
        }

        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        appState.$selectedPrinter
            .combineLatest(appState.$isSharingActive)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.menu.update()
            }
            .store(in: &cancellables)
    }

    func showWindow() {
        if window == nil {
            window = makeWindow()
        }
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let content = InkognitoWindowView()
            .environmentObject(appState)
        let hosting = NSHostingController(rootView: content)
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.contentViewController = hosting
        w.title = "Inkognito"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.setFrameAutosaveName("InkognitoMainWindow")
        w.center()
        w.delegate = self
        return w
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let printerLabel = appState.selectedPrinter?.name ?? "No printer"
        let shareLabel = appState.isSharingActive ? "Sharing" : "Off"
        let statusItem = NSMenuItem(title: "\(printerLabel) • \(shareLabel)", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open Inkognito…", action: #selector(openWindowAction), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        if appState.selectedPrinter != nil {
            let toggleTitle = appState.isSharingActive ? "Stop Sharing" : "Start Sharing"
            let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleSharingAction), keyEquivalent: "")
            toggleItem.target = self
            menu.addItem(toggleItem)
        }

        menu.addItem(.separator())

        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLoginAction), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Inkognito", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func openWindowAction() {
        showWindow()
    }

    @objc private func toggleSharingAction() {
        if appState.isSharingActive {
            appState.stopSharing()
        } else {
            appState.startSharing()
        }
    }

    @objc private func toggleLaunchAtLoginAction() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not update Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
