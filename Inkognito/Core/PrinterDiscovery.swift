import Foundation

enum PrinterDiscovery {
    nonisolated static func getPrinters() -> [PrinterInfo] {
        let names = runLPStat(arguments: ["-p"]).flatMap(parseNames) ?? []
        let devices = runLPStat(arguments: ["-v"]).flatMap(parseDevices) ?? [:]

        var infos: [PrinterInfo] = []
        for name in names {
            let model = modelHint(forName: name, devices: devices)
            infos.append(PrinterInfo(name: name, model: model))
        }
        return infos.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private nonisolated static func runLPStat(arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/lpstat")
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

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

    private nonisolated static func parseNames(from output: String) -> [String] {
        var names: [String] = []
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("printer ") else { continue }
            let remainder = trimmed.dropFirst("printer ".count)
            if let nameEnd = remainder.firstIndex(where: { $0.isWhitespace }) {
                let name = String(remainder[..<nameEnd])
                if !name.isEmpty { names.append(name) }
            }
        }
        return names
    }

    private nonisolated static func parseDevices(from output: String) -> [String: String] {
        var devices: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("device for ") else { continue }
            let remainder = trimmed.dropFirst("device for ".count)
            guard let colon = remainder.firstIndex(of: ":") else { continue }
            let name = String(remainder[..<colon]).trimmingCharacters(in: .whitespaces)
            let uri = String(remainder[remainder.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                devices[name] = uri
            }
        }
        return devices
    }

    private nonisolated static func modelHint(forName name: String, devices: [String: String]) -> String {
        if let uri = devices[name], let model = modelFrom(uri: uri) {
            return model
        }
        return name.replacingOccurrences(of: "_", with: " ")
    }

    private nonisolated static func modelFrom(uri: String) -> String? {
        if uri.hasPrefix("usb://") {
            let stripped = uri.dropFirst("usb://".count)
            let parts = stripped.split(separator: "?", maxSplits: 1).first.map(String.init) ?? String(stripped)
            let segments = parts.split(separator: "/").map(String.init)
            if segments.count >= 2 {
                let brand = decodeURIComponent(segments[0])
                let model = decodeURIComponent(segments[1])
                return "\(brand) \(model)"
            }
            return decodeURIComponent(parts.replacingOccurrences(of: "/", with: " "))
        }
        if let host = URL(string: uri)?.host {
            return host
        }
        return nil
    }

    private nonisolated static func decodeURIComponent(_ s: String) -> String {
        s.removingPercentEncoding ?? s
    }
}
