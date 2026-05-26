import Foundation

nonisolated final class CUPSSharingManager: @unchecked Sendable {
    struct CUPSError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func enableSharing(printerName: String) throws {
        try run(["/usr/sbin/lpadmin", "-p", printerName, "-o", "printer-is-shared=true"])
        // Without -u allow:all cupsd returns client-error-not-authorized for
        // Create-Job from anonymous clients (iOS AirPrint connects without
        // authentication). This is the missing piece AirPrint_Bridge applies.
        try run(["/usr/sbin/lpadmin", "-p", printerName, "-u", "allow:all"])
    }

    func disableSharing(printerName: String) throws {
        try run(["/usr/sbin/lpadmin", "-p", printerName, "-o", "printer-is-shared=false"])
    }

    func isSharingEnabled(printerName: String) -> Bool {
        guard let output = runCapturing(["/usr/bin/lpoptions", "-p", printerName]) else { return false }
        return output.contains("printer-is-shared=true")
    }

    /// True when cupsd is configured to accept LAN connections.
    /// Maps to the "Printer Sharing" toggle in System Settings → Sharing.
    func isSystemSharingEnabled() -> Bool {
        guard let output = runCapturing(["/usr/sbin/cupsctl"]) else { return false }
        return output.contains("_share_printers=1")
    }

    /// Attempt to flip the system-wide Printer Sharing switch on. Requires
    /// the running user to be in the _lpadmin group (default for macOS admins).
    /// Returns true if the setting is now enabled.
    @discardableResult
    func enableSystemSharing() -> Bool {
        _ = runCapturing(["/usr/sbin/cupsctl", "--share-printers", "--remote-any"])
        return isSystemSharingEnabled()
    }

    private func run(_ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0])
        process.arguments = Array(args.dropFirst())
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            throw CUPSError(message: "Could not launch \(args[0]): \(error.localizedDescription)")
        }
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? ""
            let trimmed = errStr.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = trimmed.isEmpty ? "" : " — \(trimmed)"
            throw CUPSError(message: "\(args[0]) exited \(process.terminationStatus)\(suffix)")
        }
    }

    private func runCapturing(_ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0])
        process.arguments = Array(args.dropFirst())
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
