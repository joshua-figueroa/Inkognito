import Foundation
import dnssd

nonisolated final class BonjourAdvertiser: @unchecked Sendable {
    private var sdRef: DNSServiceRef?
    private var source: DispatchSourceRead?
    private let queue: DispatchQueue
    private(set) var isRunning: Bool = false

    init(queue: DispatchQueue = .inkognitoNetwork) {
        self.queue = queue
    }

    deinit {
        if let sdRef {
            DNSServiceRefDeallocate(sdRef)
        }
        source?.cancel()
    }

    @discardableResult
    func start(printerName: String, model: String, port: UInt16) -> Bool {
        stop()

        var txt = TXTRecordRef()
        TXTRecordCreate(&txt, 0, nil)
        defer { TXTRecordDeallocate(&txt) }

        let sanitizedResource = printerName
            .replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? printerName

        let pairs: [(String, String)] = [
            ("txtvers", "1"),
            ("qtotal", "1"),
            ("rp", "printers/\(sanitizedResource)"),
            ("ty", model.isEmpty ? printerName : model),
            ("adminurl", "http://localhost:\(port)/"),
            ("note", ""),
            ("priority", "0"),
            ("product", "(Inkognito)"),
            ("pdl", "application/pdf,image/jpeg")
        ]

        for (key, value) in pairs {
            let bytes = Array(value.utf8)
            let err = bytes.withUnsafeBufferPointer { buffer -> DNSServiceErrorType in
                key.withCString { keyPtr in
                    TXTRecordSetValue(&txt, keyPtr, UInt8(buffer.count), buffer.baseAddress)
                }
            }
            if err != kDNSServiceErr_NoError {
                return false
            }
        }

        let displayName = "\(printerName) (Inkognito)"
        let regtype = "_ipp._tcp,_universal"
        let txtLen = TXTRecordGetLength(&txt)
        let txtPtr = TXTRecordGetBytesPtr(&txt)
        let portNet = port.bigEndian

        var localRef: DNSServiceRef?
        let registerErr = displayName.withCString { namePtr in
            regtype.withCString { typePtr in
                DNSServiceRegister(
                    &localRef,
                    0,
                    0,
                    namePtr,
                    typePtr,
                    nil,
                    nil,
                    portNet,
                    txtLen,
                    txtPtr,
                    Self.registerCallback,
                    nil
                )
            }
        }

        guard registerErr == kDNSServiceErr_NoError, let localRef else {
            return false
        }

        sdRef = localRef

        let fd = DNSServiceRefSockFD(localRef)
        guard fd >= 0 else {
            DNSServiceRefDeallocate(localRef)
            sdRef = nil
            return false
        }

        let readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        readSource.setEventHandler { [weak self] in
            guard let self, let ref = self.sdRef else { return }
            DNSServiceProcessResult(ref)
        }
        readSource.resume()
        source = readSource

        isRunning = true
        return true
    }

    func stop() {
        source?.cancel()
        source = nil
        if let sdRef {
            DNSServiceRefDeallocate(sdRef)
        }
        sdRef = nil
        isRunning = false
    }

    private static let registerCallback: DNSServiceRegisterReply = { _, _, _, _, _, _, _ in
        // No-op: registration confirmation arrives here. We rely on the
        // initial DNSServiceRegister return value to detect failures.
    }
}
