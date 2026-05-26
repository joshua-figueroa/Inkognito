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
    private var ippServer: IPPServer?
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

    func bind(advertiser: BonjourAdvertiser, ippServer: IPPServer) {
        self.advertiser = advertiser
        self.ippServer = ippServer

        ippServer.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                switch event {
                case .received(let job):
                    self.appendJob(job)
                    Notifier.jobReceived(printerName: job.printerName)
                case .finished(let id, let status, let pageCount):
                    self.updateJob(id: id, status: status, pageCount: pageCount)
                }
            }
            .store(in: &cancellables)
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
        guard let advertiser, let ippServer else { return }
        DispatchQueue.inkognitoNetwork.async { [weak self] in
            do {
                let port = try ippServer.start(port: 631)
                ippServer.setActivePrinter(printer.name)
                let ok = advertiser.start(
                    printerName: printer.name,
                    model: printer.model,
                    port: port
                )
                if !ok {
                    ippServer.stop()
                    DispatchQueue.main.async {
                        self?.lastError = "Bonjour registration failed."
                        self?.isSharingActive = false
                    }
                    return
                }
                DispatchQueue.main.async {
                    self?.isSharingActive = true
                    self?.lastError = nil
                    Notifier.shareStarted(printerName: printer.name)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.lastError = "Could not start sharing: \(error.localizedDescription)"
                    self?.isSharingActive = false
                }
            }
        }
    }

    func stopSharing() {
        guard let advertiser, let ippServer else {
            isSharingActive = false
            return
        }
        DispatchQueue.inkognitoNetwork.async { [weak self] in
            advertiser.stop()
            ippServer.stop()
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
