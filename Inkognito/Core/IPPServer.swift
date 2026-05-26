import Combine
import Darwin
import Foundation
import Network

nonisolated final class IPPServer: @unchecked Sendable {
    let events = PassthroughSubject<JobEvent, Never>()

    private let queue: DispatchQueue
    private let forwarder: JobForwarder
    private var listener: NWListener?
    private var activePrinterName: String?
    private var boundPort: UInt16 = 0

    init(forwarder: JobForwarder, queue: DispatchQueue = .inkognitoNetwork) {
        self.forwarder = forwarder
        self.queue = queue
    }

    deinit { stop() }

    func setActivePrinter(_ name: String) {
        queue.async { [weak self] in
            self?.activePrinterName = name
        }
    }

    @discardableResult
    func start(port preferred: UInt16 = 631) throws -> UInt16 {
        stop()

        let candidates: [UInt16] = preferred == 631 ? [631, 8631] : [preferred, 8631]
        var lastError: Error?

        for candidate in candidates {
            if !canBind(port: candidate) {
                lastError = NSError(
                    domain: "Inkognito.IPPServer",
                    code: Int(EADDRINUSE),
                    userInfo: [NSLocalizedDescriptionKey: "Port \(candidate) is in use"]
                )
                continue
            }
            do {
                let nwPort = NWEndpoint.Port(rawValue: candidate)!
                let l = try NWListener(using: .tcp, on: nwPort)
                l.newConnectionHandler = { [weak self] conn in
                    guard let self else { return }
                    HTTPConnection(
                        connection: conn,
                        queue: self.queue,
                        handler: self.handle(request:)
                    ).start()
                }
                l.start(queue: queue)
                listener = l
                boundPort = candidate
                return candidate
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError ?? NSError(
            domain: "Inkognito.IPPServer",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Could not bind any candidate port"]
        )
    }

    func stop() {
        listener?.cancel()
        listener = nil
        boundPort = 0
    }

    private func canBind(port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = in_addr_t(0).bigEndian
        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return bindResult == 0
    }

    private func handle(request: HTTPRequest) -> HTTPResponse {
        guard request.method == "POST" else {
            return HTTPResponse.text(status: "405 Method Not Allowed", body: "POST required")
        }

        let activeName = activePrinterName
        let pathOK: Bool = {
            if request.path == "/ipp/print" { return true }
            if let activeName,
               let decoded = request.path.removingPercentEncoding,
               decoded == "/printers/\(activeName)" || decoded == "/printers/\(activeName.replacingOccurrences(of: " ", with: "_"))" {
                return true
            }
            return false
        }()
        if !pathOK {
            return HTTPResponse.text(status: "404 Not Found", body: "No such printer resource")
        }

        let contentType = request.headers["content-type"]?.lowercased() ?? ""
        if !contentType.hasPrefix("application/ipp") {
            return HTTPResponse.text(status: "415 Unsupported Media Type", body: "application/ipp required")
        }

        guard let (message, payload) = IPPCodec.parse(request.body) else {
            return ippErrorResponse(operation: 0, requestID: 0, status: 0x0400) // client-error-bad-request
        }

        switch message.operation {
        case 0x000B:
            return handleGetPrinterAttributes(message)
        case 0x0004:
            return handleValidateJob(message)
        case 0x0002:
            return handlePrintJob(message, payload: payload, userAgent: request.headers["user-agent"])
        default:
            return ippErrorResponse(
                operation: message.operation,
                requestID: message.requestID,
                status: 0x0501
            )
        }
    }

    private var advertisedPrinterURI: String {
        let host = ProcessInfo.processInfo.hostName
        return "ipp://\(host):\(boundPort)/ipp/print"
    }

    private func handleGetPrinterAttributes(_ msg: IPPMessage) -> HTTPResponse {
        let name = activePrinterName ?? "Inkognito"

        var response = IPPMessage(
            versionMajor: 1, versionMinor: 1,
            statusOrOperation: 0x0000,
            requestID: msg.requestID,
            attributes: []
        )
        response.attributes.append(contentsOf: operationAttributesGroup())

        let printerAttrs: [IPPAttribute] = [
            .init(group: 0x04, name: "printer-uri-supported", tag: 0x45, values: [.string(advertisedPrinterURI)]),
            .init(group: 0x04, name: "uri-authentication-supported", tag: 0x44, values: [.string("none")]),
            .init(group: 0x04, name: "uri-security-supported", tag: 0x44, values: [.string("none")]),
            .init(group: 0x04, name: "printer-name", tag: 0x42, values: [.string(name)]),
            .init(group: 0x04, name: "printer-state", tag: 0x23, values: [.integer(3)]),
            .init(group: 0x04, name: "printer-state-reasons", tag: 0x44, values: [.string("none")]),
            .init(group: 0x04, name: "ipp-versions-supported", tag: 0x44, values: [.string("1.1")]),
            .init(group: 0x04, name: "operations-supported", tag: 0x23, values: [.integer(0x0002), .integer(0x0004), .integer(0x000B)]),
            .init(group: 0x04, name: "charset-configured", tag: 0x47, values: [.string("utf-8")]),
            .init(group: 0x04, name: "charset-supported", tag: 0x47, values: [.string("utf-8")]),
            .init(group: 0x04, name: "natural-language-configured", tag: 0x48, values: [.string("en-us")]),
            .init(group: 0x04, name: "generated-natural-language-supported", tag: 0x48, values: [.string("en-us")]),
            .init(group: 0x04, name: "document-format-default", tag: 0x49, values: [.string("application/pdf")]),
            .init(group: 0x04, name: "document-format-supported", tag: 0x49, values: [.string("application/pdf"), .string("image/jpeg")]),
            .init(group: 0x04, name: "printer-is-accepting-jobs", tag: 0x22, values: [.boolean(true)]),
            .init(group: 0x04, name: "queued-job-count", tag: 0x21, values: [.integer(0)]),
            .init(group: 0x04, name: "pdl-override-supported", tag: 0x44, values: [.string("not-attempted")]),
            .init(group: 0x04, name: "color-supported", tag: 0x22, values: [.boolean(true)]),
            .init(group: 0x04, name: "sides-supported", tag: 0x44, values: [.string("one-sided")]),
            .init(group: 0x04, name: "media-default", tag: 0x44, values: [.string("iso_a4_210x297mm")]),
            .init(group: 0x04, name: "media-supported", tag: 0x44, values: [.string("iso_a4_210x297mm"), .string("na_letter_8.5x11in")])
        ]
        response.attributes.append(contentsOf: printerAttrs)
        return HTTPResponse.ipp(body: IPPCodec.encode(response))
    }

    private func handleValidateJob(_ msg: IPPMessage) -> HTTPResponse {
        let response = IPPMessage(
            versionMajor: 1, versionMinor: 1,
            statusOrOperation: 0x0000,
            requestID: msg.requestID,
            attributes: operationAttributesGroup()
        )
        return HTTPResponse.ipp(body: IPPCodec.encode(response))
    }

    private func handlePrintJob(_ msg: IPPMessage, payload: Data, userAgent: String?) -> HTTPResponse {
        let printerName = activePrinterName ?? "Inkognito"
        let documentName = msg.stringAttribute("document-name") ?? "AirPrint Job"
        let source = parseSourceDevice(userAgent: userAgent)

        let job = PrintJob(
            printerName: printerName,
            sourceDevice: source,
            status: .pending
        )
        events.send(.received(job))

        let result = forwarder.forward(payload, to: printerName, jobName: documentName)
        let finalStatus: PrintJobStatus = result.didSucceed
            ? .done
            : .failed(result.error?.localizedDescription)
        events.send(.finished(id: job.id, status: finalStatus, pageCount: result.pageCount))

        var response = IPPMessage(
            versionMajor: 1, versionMinor: 1,
            statusOrOperation: 0x0000,
            requestID: msg.requestID,
            attributes: operationAttributesGroup()
        )
        let jobURI = "\(advertisedPrinterURI)/\(job.id.uuidString)"
        let jobStateValue: Int32 = result.didSucceed ? 9 : 8
        response.attributes.append(contentsOf: [
            .init(group: 0x02, name: "job-uri", tag: 0x45, values: [.string(jobURI)]),
            .init(group: 0x02, name: "job-id", tag: 0x21, values: [.integer(Int32(abs(job.id.hashValue % 100_000)))]),
            .init(group: 0x02, name: "job-state", tag: 0x23, values: [.integer(jobStateValue)]),
            .init(group: 0x02, name: "job-state-reasons", tag: 0x44, values: [.string(result.didSucceed ? "job-completed-successfully" : "job-completed-with-errors")])
        ])
        return HTTPResponse.ipp(body: IPPCodec.encode(response))
    }

    private func operationAttributesGroup() -> [IPPAttribute] {
        [
            .init(group: 0x01, name: "attributes-charset", tag: 0x47, values: [.string("utf-8")]),
            .init(group: 0x01, name: "attributes-natural-language", tag: 0x48, values: [.string("en-us")])
        ]
    }

    private func ippErrorResponse(operation: UInt16, requestID: UInt32, status: UInt16) -> HTTPResponse {
        let response = IPPMessage(
            versionMajor: 1, versionMinor: 1,
            statusOrOperation: status,
            requestID: requestID,
            attributes: operationAttributesGroup()
        )
        return HTTPResponse.ipp(body: IPPCodec.encode(response))
    }

    private func parseSourceDevice(userAgent: String?) -> String {
        guard let ua = userAgent else { return "Unknown" }
        if ua.contains("iPhone") { return "iPhone" }
        if ua.contains("iPad") { return "iPad" }
        if ua.contains("iOS") { return "iOS" }
        if ua.contains("Mac") || ua.contains("CUPS") || ua.contains("Darwin") { return "Mac" }
        return "Device"
    }
}

// MARK: - HTTP layer

nonisolated fileprivate struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]   // lowercased keys
    let body: Data
}

nonisolated fileprivate struct HTTPResponse {
    let status: String
    let contentType: String
    let body: Data

    static func ipp(body: Data) -> HTTPResponse {
        HTTPResponse(status: "200 OK", contentType: "application/ipp", body: body)
    }

    static func text(status: String, body: String) -> HTTPResponse {
        HTTPResponse(status: status, contentType: "text/plain; charset=utf-8", body: Data(body.utf8))
    }

    func serialize() -> Data {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        return out
    }
}

nonisolated fileprivate final class HTTPConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let handler: (HTTPRequest) -> HTTPResponse

    private var headerBuffer = Data()
    private var pending = Data()
    private var parsedHeaders: ParsedHeaders?
    private var body = Data()

    private struct ParsedHeaders {
        let method: String
        let path: String
        let headers: [String: String]
        let contentLength: Int?
        let isChunked: Bool
        let expectsContinue: Bool
    }

    private static let crlfcrlf = Data([0x0D, 0x0A, 0x0D, 0x0A])
    private static let crlf = Data([0x0D, 0x0A])

    init(connection: NWConnection, queue: DispatchQueue, handler: @escaping (HTTPRequest) -> HTTPResponse) {
        self.connection = connection
        self.queue = queue
        self.handler = handler
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.connection.cancel()
            default: break
            }
        }
        connection.start(queue: queue)
        readHeaders()
    }

    private func readHeaders() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.headerBuffer.append(data)
                if let split = self.headerBuffer.range(of: Self.crlfcrlf) {
                    let headerData = self.headerBuffer.subdata(in: 0..<split.lowerBound)
                    let leftover = self.headerBuffer.subdata(in: split.upperBound..<self.headerBuffer.count)
                    self.headerBuffer.removeAll()
                    self.pending = leftover
                    self.parseHeaders(headerData)
                    return
                }
                if self.headerBuffer.count > 64 * 1024 {
                    self.fail("Header too large")
                    return
                }
            }
            if isComplete || error != nil {
                self.fail("Connection closed before headers complete")
                return
            }
            self.readHeaders()
        }
    }

    private func parseHeaders(_ data: Data) {
        guard let headerString = String(data: data, encoding: .utf8) else {
            fail("Invalid header encoding")
            return
        }
        let lines = headerString.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        guard let requestLine = lines.first else {
            fail("Empty headers")
            return
        }
        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else {
            fail("Bad request line")
            return
        }
        let method = String(parts[0])
        let path = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let contentLength = headers["content-length"].flatMap { Int($0) }
        let isChunked = (headers["transfer-encoding"]?.lowercased() ?? "").contains("chunked")
        let expectsContinue = (headers["expect"]?.lowercased() ?? "").contains("100-continue")

        parsedHeaders = ParsedHeaders(
            method: method,
            path: path,
            headers: headers,
            contentLength: contentLength,
            isChunked: isChunked,
            expectsContinue: expectsContinue
        )

        if expectsContinue {
            sendRaw(Data("HTTP/1.1 100 Continue\r\n\r\n".utf8)) { [weak self] in
                self?.readBody()
            }
        } else {
            readBody()
        }
    }

    private func readBody() {
        guard let headers = parsedHeaders else { fail("No headers"); return }

        if headers.isChunked {
            readChunked()
            return
        }

        guard let length = headers.contentLength else {
            finishRequest()
            return
        }

        if pending.count >= length {
            body = pending.subdata(in: 0..<length)
            pending = Data()
            finishRequest()
            return
        }

        body = pending
        pending = Data()
        readUntilContentLength(remaining: length - body.count)
    }

    private func readUntilContentLength(remaining: Int) {
        if remaining <= 0 {
            finishRequest()
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: min(remaining, 64 * 1024)) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.body.append(data)
            }
            let stillNeeded = remaining - (data?.count ?? 0)
            if stillNeeded <= 0 {
                self.finishRequest()
                return
            }
            if isComplete || error != nil {
                self.fail("Connection closed before body complete")
                return
            }
            self.readUntilContentLength(remaining: stillNeeded)
        }
    }

    private func readChunked() {
        if let nextChunk = consumeChunk(from: &pending) {
            switch nextChunk {
            case .data(let chunk):
                body.append(chunk)
                readChunked()
            case .end:
                finishRequest()
            case .needMore:
                break
            }
        }
        // need more bytes
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.pending.append(data)
            }
            if isComplete || error != nil {
                self.fail("Connection closed during chunked body")
                return
            }
            self.readChunked()
        }
    }

    private enum ChunkResult {
        case data(Data)
        case end
        case needMore
    }

    private func consumeChunk(from buffer: inout Data) -> ChunkResult? {
        guard let lineEnd = buffer.range(of: Self.crlf) else { return .needMore }
        let lineBytes = buffer.subdata(in: 0..<lineEnd.lowerBound)
        guard let lineStr = String(data: lineBytes, encoding: .utf8) else {
            return .needMore
        }
        let sizeStr = lineStr.split(separator: ";").first.map(String.init) ?? lineStr
        guard let size = Int(sizeStr, radix: 16) else {
            return .needMore
        }
        let afterHeader = lineEnd.upperBound
        let needed = afterHeader + size + 2 // chunk + trailing CRLF
        if buffer.count < needed { return .needMore }

        if size == 0 {
            // trailing CRLF after 0-size already consumed by `needed`
            buffer.removeSubrange(0..<needed)
            return .end
        }

        let chunkData = buffer.subdata(in: afterHeader..<(afterHeader + size))
        buffer.removeSubrange(0..<needed)
        return .data(chunkData)
    }

    private func finishRequest() {
        guard let headers = parsedHeaders else { fail("No headers on finish"); return }
        let req = HTTPRequest(
            method: headers.method,
            path: headers.path,
            headers: headers.headers,
            body: body
        )
        let response = handler(req)
        sendRaw(response.serialize()) { [weak self] in
            self?.connection.cancel()
        }
    }

    private func sendRaw(_ data: Data, completion: @escaping () -> Void) {
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if error != nil {
                self?.connection.cancel()
                return
            }
            completion()
        })
    }

    private func fail(_ reason: String) {
        let body = Data("\(reason)\n".utf8)
        let head = "HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        connection.send(content: out, completion: .contentProcessed { [weak self] _ in
            self?.connection.cancel()
        })
    }
}

// MARK: - IPP codec

nonisolated fileprivate enum IPPValue {
    case integer(Int32)
    case boolean(Bool)
    case string(String)
    case raw(Data)
}

nonisolated fileprivate struct IPPAttribute {
    let group: UInt8
    let name: String
    let tag: UInt8
    let values: [IPPValue]
}

nonisolated fileprivate struct IPPMessage {
    let versionMajor: UInt8
    let versionMinor: UInt8
    let statusOrOperation: UInt16
    let requestID: UInt32
    var attributes: [IPPAttribute]

    var operation: UInt16 { statusOrOperation }

    func stringAttribute(_ name: String) -> String? {
        for attr in attributes where attr.name == name {
            for value in attr.values {
                if case .string(let s) = value { return s }
            }
        }
        return nil
    }
}

nonisolated fileprivate enum IPPCodec {
    static func parse(_ data: Data) -> (IPPMessage, Data)? {
        guard data.count >= 8 else { return nil }
        let versionMajor = data[data.startIndex]
        let versionMinor = data[data.startIndex + 1]
        let operation = readUInt16(data, at: data.startIndex + 2)
        let requestID = readUInt32(data, at: data.startIndex + 4)

        var index = data.startIndex + 8
        var attributes: [IPPAttribute] = []
        var currentGroup: UInt8 = 0
        var lastAttribute: (group: UInt8, name: String, tag: UInt8, values: [IPPValue])?

        while index < data.endIndex {
            let tag = data[index]
            index += 1

            if tag >= 0x01 && tag <= 0x05 {
                if let last = lastAttribute {
                    attributes.append(.init(group: last.group, name: last.name, tag: last.tag, values: last.values))
                    lastAttribute = nil
                }
                if tag == 0x03 {
                    let remaining = (index < data.endIndex) ? data.subdata(in: index..<data.endIndex) : Data()
                    return (
                        IPPMessage(
                            versionMajor: versionMajor,
                            versionMinor: versionMinor,
                            statusOrOperation: operation,
                            requestID: requestID,
                            attributes: attributes
                        ),
                        remaining
                    )
                }
                currentGroup = tag
                continue
            }

            // value tag
            guard index + 2 <= data.endIndex else { return nil }
            let nameLen = Int(readUInt16(data, at: index))
            index += 2
            guard index + nameLen <= data.endIndex else { return nil }
            let nameBytes = data.subdata(in: index..<(index + nameLen))
            index += nameLen
            let name = String(data: nameBytes, encoding: .utf8) ?? ""

            guard index + 2 <= data.endIndex else { return nil }
            let valueLen = Int(readUInt16(data, at: index))
            index += 2
            guard index + valueLen <= data.endIndex else { return nil }
            let valueBytes = data.subdata(in: index..<(index + valueLen))
            index += valueLen

            let parsed = decodeValue(tag: tag, data: valueBytes)

            if nameLen == 0, var last = lastAttribute, last.tag == tag {
                last.values.append(parsed)
                lastAttribute = last
            } else {
                if let last = lastAttribute {
                    attributes.append(.init(group: last.group, name: last.name, tag: last.tag, values: last.values))
                }
                lastAttribute = (currentGroup, name, tag, [parsed])
            }
        }

        if let last = lastAttribute {
            attributes.append(.init(group: last.group, name: last.name, tag: last.tag, values: last.values))
        }

        return (
            IPPMessage(
                versionMajor: versionMajor,
                versionMinor: versionMinor,
                statusOrOperation: operation,
                requestID: requestID,
                attributes: attributes
            ),
            Data()
        )
    }

    static func encode(_ message: IPPMessage) -> Data {
        var out = Data()
        out.append(message.versionMajor)
        out.append(message.versionMinor)
        out.append(uint16BE(message.statusOrOperation))
        out.append(uint32BE(message.requestID))

        var currentGroup: UInt8 = 0
        for attr in message.attributes {
            if attr.group != currentGroup {
                out.append(attr.group)
                currentGroup = attr.group
            }
            for (i, value) in attr.values.enumerated() {
                out.append(attr.tag)
                if i == 0 {
                    let nameBytes = Array(attr.name.utf8)
                    out.append(uint16BE(UInt16(nameBytes.count)))
                    out.append(contentsOf: nameBytes)
                } else {
                    out.append(uint16BE(0))
                }
                let valueData = encodeValue(tag: attr.tag, value: value)
                out.append(uint16BE(UInt16(valueData.count)))
                out.append(valueData)
            }
        }

        out.append(0x03)
        return out
    }

    private static func decodeValue(tag: UInt8, data: Data) -> IPPValue {
        switch tag {
        case 0x21, 0x23:
            if data.count == 4 {
                let raw = readUInt32(data, at: data.startIndex)
                return .integer(Int32(bitPattern: raw))
            }
            return .raw(data)
        case 0x22:
            return .boolean((data.first ?? 0) != 0)
        case 0x30, 0x31:
            return .raw(data)
        default:
            return .string(String(data: data, encoding: .utf8) ?? "")
        }
    }

    private static func encodeValue(tag: UInt8, value: IPPValue) -> Data {
        switch value {
        case .integer(let i):
            return uint32BE(UInt32(bitPattern: i))
        case .boolean(let b):
            return Data([b ? 1 : 0])
        case .string(let s):
            return Data(s.utf8)
        case .raw(let d):
            return d
        }
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        let hi = UInt16(data[offset])
        let lo = UInt16(data[offset + 1])
        return (hi << 8) | lo
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        var result: UInt32 = 0
        result |= UInt32(data[offset]) << 24
        result |= UInt32(data[offset + 1]) << 16
        result |= UInt32(data[offset + 2]) << 8
        result |= UInt32(data[offset + 3])
        return result
    }

    private static func uint16BE(_ v: UInt16) -> Data {
        Data([UInt8(v >> 8), UInt8(v & 0xFF)])
    }

    private static func uint32BE(_ v: UInt32) -> Data {
        Data([
            UInt8((v >> 24) & 0xFF),
            UInt8((v >> 16) & 0xFF),
            UInt8((v >> 8) & 0xFF),
            UInt8(v & 0xFF)
        ])
    }
}
