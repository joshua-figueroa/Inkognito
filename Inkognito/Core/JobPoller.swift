import Foundation

/// Polls `lpstat -o <printer>` and reports the currently-active CUPS jobs.
/// AppState diffs the snapshot against the previous one to derive
/// PrintJob lifecycle events (appeared = received, disappeared = completed).
nonisolated final class JobPoller: @unchecked Sendable {
    struct ActiveJob: Equatable, Sendable {
        let cupsID: String      // e.g. "Canon_G2020_series-5"
        let user: String        // submitter user name from lpstat
        let sizeBytes: Int      // bytes in the queued document
        let documentName: String?
    }

    private let onSnapshot: ([ActiveJob]) -> Void
    private let queue: DispatchQueue
    private let pollInterval: TimeInterval
    private var timer: DispatchSourceTimer?
    private var printerName: String?

    init(
        queue: DispatchQueue = .inkognitoNetwork,
        pollInterval: TimeInterval = 3.0,
        onSnapshot: @escaping ([ActiveJob]) -> Void
    ) {
        self.queue = queue
        self.pollInterval = pollInterval
        self.onSnapshot = onSnapshot
    }

    deinit { stop() }

    func start(printerName: String) {
        stop()
        self.printerName = printerName
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .milliseconds(100), repeating: pollInterval, leeway: .milliseconds(500))
        t.setEventHandler { [weak self] in self?.poll() }
        timer = t
        t.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        printerName = nil
    }

    private func poll() {
        guard let printerName else { return }
        let jobs = JobPoller.queryActive(printer: printerName)
        DispatchQueue.main.async { [onSnapshot] in
            onSnapshot(jobs)
        }
    }

    private static func queryActive(printer: String) -> [ActiveJob] {
        guard let statOut = shell("/usr/bin/lpstat", "-o", printer) else { return [] }

        var basicJobs: [(cupsID: String, user: String, size: Int)] = []
        for rawLine in statOut.split(separator: "\n") {
            let parts = rawLine.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 3 else { continue }
            basicJobs.append((String(parts[0]), String(parts[1]), Int(parts[2]) ?? 0))
        }
        guard !basicJobs.isEmpty else { return [] }

        // lpq -P <printer> format:
        // Rank    Owner   Job  File(s)             Total Size
        // active  mobile  5    Document.pdf         61440 bytes
        var docByJobNum: [String: String] = [:]
        if let lpqOut = shell("/usr/bin/lpq", "-P", printer) {
            for line in lpqOut.components(separatedBy: "\n") {
                let parts = line.split(whereSeparator: \.isWhitespace)
                guard parts.count >= 6 else { continue }
                let jobNum = String(parts[2])
                guard Int(jobNum) != nil else { continue }   // skip header
                let nameParts = parts[3 ..< (parts.count - 2)]
                let name = nameParts.joined(separator: " ")
                if !name.isEmpty { docByJobNum[jobNum] = name }
            }
        }

        return basicJobs.map { job in
            let jobNum = job.cupsID.components(separatedBy: "-").last ?? ""
            return ActiveJob(cupsID: job.cupsID, user: job.user, sizeBytes: job.size,
                             documentName: docByJobNum[jobNum])
        }
    }

    private static func shell(_ path: String, _ args: String...) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run(); p.waitUntilExit() } catch { return nil }
        guard p.terminationStatus == 0 else { return nil }
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}
