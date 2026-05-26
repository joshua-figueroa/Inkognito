import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var appState: AppState!
    private(set) var menuBarController: MenuBarController!
    private var advertiser: BonjourAdvertiser!
    private var cupsManager: CUPSSharingManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
        NSApp.setActivationPolicy(.accessory)

        advertiser = BonjourAdvertiser()
        cupsManager = CUPSSharingManager()

        appState = AppState()
        appState.bind(advertiser: advertiser, cupsManager: cupsManager)
        menuBarController = MenuBarController(appState: appState)

        Notifier.requestAuth()

        appState.loadPersisted()
        appState.refreshPrinters()

        // The refresh is asynchronous; give it up to ~600 ms then decide
        // whether to auto-resume sharing or reveal the window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            if let selected = self.appState.selectedPrinter,
               self.appState.printers.contains(where: { $0.name == selected.name }) {
                self.appState.startSharing()
            } else {
                self.menuBarController.showWindow()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.stopSharing()
    }
}

@MainActor
enum Notifier {
    private static var lastJobNotification: Date?
    private static let throttleInterval: TimeInterval = 5

    static func requestAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            // ignore; if denied, notifications simply won't appear
        }
    }

    static func shareStarted(printerName: String) {
        post(
            title: "🕵️ Gone undercover",
            body: "\(printerName) is now AirPrint-ready"
        )
    }

    static func jobReceived(printerName: String) {
        let now = Date()
        if let last = lastJobNotification, now.timeIntervalSince(last) < throttleInterval {
            return
        }
        lastJobNotification = now
        post(
            title: "🖨️ Mission accepted",
            body: "printing to \(printerName)"
        )
    }

    private static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in
            // ignore errors
        }
    }
}
