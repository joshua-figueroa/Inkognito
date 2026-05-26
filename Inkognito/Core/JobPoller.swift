import Foundation

/// Polls `lpstat -o <printer>` and reports the currently-active CUPS jobs.
/// AppState diffs the snapshot against the previous one to derive
/// PrintJob lifecycle events (appeared = received, disappeared = completed).
nonisolated final class JobPoller: @unchecked Sendable {
    struct ActiveJob: Equatable, Sendable {
        let cupsID: String      // e.g. "Canon_G2020_series-5"
        let user: String        // submitter user name from lpstat
        let sizeBytes: Int      // bytes in the queued document
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/lpstat")
        process.arguments = ["-o", printer]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        guard process.terminationStatus == 0 else { return [] }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var jobs: [ActiveJob] = []
        for rawLine in output.split(separator: "\n") {
            let parts = rawLine.split(whereSeparator: { $0.isWhitespace })
            // Expected: <job-id> <user> <size> <date...>
            guard parts.count >= 3 else { continue }
            let id = String(parts[0])
            let user = String(parts[1])
            let size = Int(parts[2]) ?? 0
            jobs.append(ActiveJob(cupsID: id, user: user, sizeBytes: size))
        }
        return jobs
    }
}
