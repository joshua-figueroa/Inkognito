import Combine
import Foundation

extension DispatchQueue {
    nonisolated static let inkognitoNetwork = DispatchQueue(
        label: "com.inkognito.network",
        qos: .userInitiated
    )
}

final class AppState: ObservableObject {
    @Published var printers: [PrinterInfo]
    @Published var selectedPrinter: PrinterInfo?
    @Published var isSharingActive: Bool
    @Published var recentJobs: [PrintJob]
    @Published var lastError: String?

    private static let selectedPrinterKey = "selectedPrinter"
    private static let recentJobsCap = 50
    private static let displayedJobsCap = 10

    private var advertiser: BonjourAdvertiser?
    private var cupsManager: CUPSSharingManager?
    private var jobPoller: JobPoller?
    private var trackedJobs: [String: UUID] = [:]   // CUPS job ID → PrintJob UUID
    private var pendingSelectedName: String?
    private var cancellables = Set<AnyCancellable>()

    init(
        printers: [PrinterInfo] = [],
        selectedPrinter: PrinterInfo? = nil,
        isSharingActive: Bool = false,
        recentJobs: [PrintJob] = []
    ) {
        self.printers = printers
        self.selectedPrinter = selectedPrinter
        self.isSharingActive = isSharingActive
        self.recentJobs = recentJobs
    }

    func bind(advertiser: BonjourAdvertiser, cupsManager: CUPSSharingManager) {
        self.advertiser = advertiser
        self.cupsManager = cupsManager
        self.jobPoller = JobPoller { [weak self] active in
            self?.applyActiveJobs(active)
        }
    }

    private func applyActiveJobs(_ active: [JobPoller.ActiveJob]) {
        guard let printerName = selectedPrinter?.name else { return }
        let activeIDs = Set(active.map { $0.cupsID })

        // Newly seen jobs → append as pending and surface a notification.
        for job in active where trackedJobs[job.cupsID] == nil {
            let uuid = UUID()
            trackedJobs[job.cupsID] = uuid
            let lowered = job.user.lowercased()
            let source = (lowered.isEmpty || lowered == "anonymous" || lowered == "ipp") ? "AirPrint" : job.user
            let newJob = PrintJob(
                id: uuid,
                timestamp: Date(),
                printerName: printerName,
                sourceDevice: source,
                status: .pending
            )
            appendJob(newJob)
            Notifier.jobReceived(printerName: printerName)
        }

        // Jobs that fell off the active queue → mark as done. lpstat doesn't
        // distinguish completion from cancellation; we treat both as "done" here.
        let disappeared = Set(trackedJobs.keys).subtracting(activeIDs)
        for cupsID in disappeared {
            if let uuid = trackedJobs.removeValue(forKey: cupsID) {
                updateJob(id: uuid, status: .done, pageCount: nil)
            }
        }
    }

    func loadPersisted() {
        pendingSelectedName = UserDefaults.standard.string(forKey: Self.selectedPrinterKey)
    }

    func persistSelection() {
        if let name = selectedPrinter?.name {
            UserDefaults.standard.set(name, forKey: Self.selectedPrinterKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.selectedPrinterKey)
        }
    }

    func refreshPrinters() {
        DispatchQueue.inkognitoNetwork.async { [weak self] in
            let discovered = PrinterDiscovery.getPrinters()
            DispatchQueue.main.async {
                self?.applyDiscovered(discovered)
            }
        }
    }

    private func applyDiscovered(_ discovered: [PrinterInfo]) {
        printers = discovered
        if let pending = pendingSelectedName,
           let match = discovered.first(where: { $0.name == pending }) {
            selectedPrinter = match
            pendingSelectedName = nil
        } else if pendingSelectedName != nil {
            pendingSelectedName = nil
        }
        if let current = selectedPrinter,
           !discovered.contains(where: { $0.name == current.name }) {
            stopSharing()
            selectedPrinter = nil
            persistSelection()
        }
    }

    func select(_ printer: PrinterInfo?) {
        if isSharingActive { stopSharing() }
        selectedPrinter = printer
        persistSelection()
    }

    func startSharing() {
        guard let printer = selectedPrinter, !isSharingActive else { return }
        guard let advertiser, let cupsManager else { return }
        let macName = Host.current().localizedName ?? "Mac"
        let location = "\(macName) @ Inkognito"
        DispatchQueue.inkognitoNetwork.async { [weak self] in
            // Make sure cupsd will actually accept LAN connections — if the
            // system-wide Printer Sharing toggle is off, attempt to flip it
            // (succeeds silently for admins; otherwise surface a clear error).
            if !cupsManager.isSystemSharingEnabled() {
                if !cupsManager.enableSystemSharing() {
                    DispatchQueue.main.async {
                        self?.lastError = "Enable Printer Sharing in System Settings → Sharing for AirPrint to work."
                        self?.isSharingActive = false
                    }
                    return
                }
            }

            do {
                try cupsManager.enableSharing(printerName: printer.name)
            } catch {
                DispatchQueue.main.async {
                    self?.lastError = "Could not enable sharing on \(printer.name): \(error.localizedDescription)"
                    self?.isSharingActive = false
                }
                return
            }

            let ok = advertiser.start(
                printerName: printer.name,
                model: printer.model,
                location: location,
                port: 631
            )
            if !ok {
                try? cupsManager.disableSharing(printerName: printer.name)
                DispatchQueue.main.async {
                    self?.lastError = "Bonjour registration failed."
                    self?.isSharingActive = false
                }
                return
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isSharingActive = true
                self.lastError = nil
                self.jobPoller?.start(printerName: printer.name)
                Notifier.shareStarted(printerName: printer.name)
            }
        }
    }

    func stopSharing() {
        guard let advertiser, let cupsManager else {
            isSharingActive = false
            return
        }
        let printerName = selectedPrinter?.name
        jobPoller?.stop()
        trackedJobs.removeAll()
        DispatchQueue.inkognitoNetwork.async { [weak self] in
            advertiser.stop()
            if let printerName {
                try? cupsManager.disableSharing(printerName: printerName)
            }
            DispatchQueue.main.async {
                self?.isSharingActive = false
            }
        }
    }

    func appendJob(_ job: PrintJob) {
        recentJobs.append(job)
        if recentJobs.count > Self.recentJobsCap {
            recentJobs.removeFirst(recentJobs.count - Self.recentJobsCap)
        }
    }

    func updateJob(id: UUID, status: PrintJobStatus, pageCount: Int?) {
        guard let index = recentJobs.firstIndex(where: { $0.id == id }) else { return }
        recentJobs[index].status = status
        if let pageCount {
            recentJobs[index].pageCount = pageCount
        }
    }

    func clearJobs() {
        recentJobs.removeAll()
    }

    static var displayedJobsLimit: Int { displayedJobsCap }
}

#if DEBUG
extension AppState {
    static var previewEmpty: AppState { AppState() }

    static var previewIdle: AppState {
        AppState(
            printers: [.sampleHP, .sampleCanon, .sampleBrother],
            selectedPrinter: .sampleHP
        )
    }

    static var previewSharing: AppState {
        AppState(
            printers: [.sampleHP, .sampleCanon, .sampleBrother],
            selectedPrinter: .sampleHP,
            isSharingActive: true,
            recentJobs: [.sampleFailed, .sampleDone, .samplePending]
        )
    }
}
#endif
