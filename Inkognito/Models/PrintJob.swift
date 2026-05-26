import Foundation

struct PrinterInfo: Identifiable, Hashable, Codable {
    let name: String
    let model: String
    var id: String { name }
    var displayName: String { name.replacingOccurrences(of: "_", with: " ") }
}

enum PrintJobStatus: Equatable {
    case pending
    case done
    case failed(String?)
}

struct PrintJob: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let printerName: String
    var pageCount: Int?
    let sourceDevice: String?
    var status: PrintJobStatus

    nonisolated init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        printerName: String,
        pageCount: Int? = nil,
        sourceDevice: String? = nil,
        status: PrintJobStatus = .pending
    ) {
        self.id = id
        self.timestamp = timestamp
        self.printerName = printerName
        self.pageCount = pageCount
        self.sourceDevice = sourceDevice
        self.status = status
    }
}

#if DEBUG
extension PrinterInfo {
    static let sampleHP = PrinterInfo(name: "HP_LaserJet_M404n", model: "HP LaserJet Pro M404n")
    static let sampleCanon = PrinterInfo(name: "Canon_MX_Series", model: "Canon PIXMA MX490")
    static let sampleBrother = PrinterInfo(name: "Brother_HL", model: "Brother HL-L2350DW")
}

extension PrintJob {
    static let sampleDone = PrintJob(
        timestamp: Date().addingTimeInterval(-120),
        printerName: "HP_LaserJet_M404n",
        pageCount: 2,
        sourceDevice: "iPhone",
        status: .done
    )
    static let sampleFailed = PrintJob(
        timestamp: Date().addingTimeInterval(-380),
        printerName: "HP_LaserJet_M404n",
        pageCount: 5,
        sourceDevice: "iPhone",
        status: .failed("lp exit 1")
    )
    static let samplePending = PrintJob(
        printerName: "HP_LaserJet_M404n",
        pageCount: nil,
        sourceDevice: "iPad",
        status: .pending
    )
}
#endif
