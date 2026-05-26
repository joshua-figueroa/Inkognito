import Foundation
import PDFKit

nonisolated final class JobForwarder {
    struct ForwardResult {
        let pageCount: Int?
        let error: Error?
        var didSucceed: Bool { error == nil }
    }

    enum ForwardError: LocalizedError {
        case writeFailed(Error)
        case lpLaunchFailed(Error)
        case lpExited(Int32)

        var errorDescription: String? {
            switch self {
            case .writeFailed(let e): return "Could not write temp file: \(e.localizedDescription)"
            case .lpLaunchFailed(let e): return "Could not launch lp: \(e.localizedDescription)"
            case .lpExited(let code): return "lp exited with status \(code)"
            }
        }
    }

    func forward(_ data: Data, to printerName: String, jobName: String?) -> ForwardResult {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).pdf")

        do {
            try data.write(to: tmp, options: .atomic)
        } catch {
            return ForwardResult(pageCount: nil, error: ForwardError.writeFailed(error))
        }

        defer { try? FileManager.default.removeItem(at: tmp) }

        let pageCount = PDFDocument(url: tmp)?.pageCount

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/lp")
        process.arguments = [
            "-d", printerName,
            "-T", jobName ?? "Inkognito Job",
            tmp.path
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return ForwardResult(pageCount: pageCount, error: ForwardError.lpLaunchFailed(error))
        }

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            return ForwardResult(
                pageCount: pageCount,
                error: ForwardError.lpExited(process.terminationStatus)
            )
        }

        return ForwardResult(pageCount: pageCount, error: nil)
    }
}
