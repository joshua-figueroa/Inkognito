import SwiftUI

struct SupplyLevel: Identifiable {
    let id = UUID()
    let name: String
    let percent: Int
    let color: Color
}

nonisolated struct SupplyReader {
    static func fetchLevels(printerName: String) -> [SupplyLevel] {
        let script = """
        {
            NAME "Get supply levels"
            OPERATION Get-Printer-Attributes
            GROUP operation-attributes-tag
            ATTR charset attributes-charset utf-8
            ATTR naturalLanguage attributes-natural-language en
            ATTR uri printer-uri ipp://localhost/printers/\(printerName)
            ATTR keyword requested-attributes marker-colors,marker-levels,marker-names,marker-types
            STATUS successful-ok
            DISPLAY marker-colors
            DISPLAY marker-levels
            DISPLAY marker-names
            DISPLAY marker-types
        }
        """
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("inkognito_supply_\(UUID().uuidString).test")
        guard (try? script.write(to: tmpURL, atomically: true, encoding: .utf8)) != nil else { return [] }
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ipptool")
        p.arguments = ["-t", "ipp://localhost/printers/\(printerName)", tmpURL.path]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run(); p.waitUntilExit() } catch { return [] }

        let output = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        var names: [String] = []
        var levels: [Int] = []
        var colors: [String] = []
        var types: [String] = []

        for line in output.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            func vals() -> [String] {
                guard let eqIdx = t.firstIndex(of: "=") else { return [] }
                return String(t[t.index(after: eqIdx)...])
                    .trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
            }
            if t.hasPrefix("marker-names") { names = vals() }
            else if t.hasPrefix("marker-levels") { levels = vals().compactMap { Int($0) } }
            else if t.hasPrefix("marker-colors") { colors = vals() }
            else if t.hasPrefix("marker-types") { types = vals() }
        }

        guard !names.isEmpty,
              names.count == levels.count,
              names.count == colors.count,
              names.count == types.count else { return [] }

        return (0 ..< names.count).compactMap { i in
            guard types[i] == "ink-cartridge" else { return nil }
            let cleanName = names[i].components(separatedBy: "(").first?
                .trimmingCharacters(in: .whitespaces) ?? names[i]
            return SupplyLevel(name: cleanName, percent: levels[i], color: Color(hex: colors[i]))
        }
    }
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        self.init(
            red:   Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8)  & 0xFF) / 255,
            blue:  Double( rgb        & 0xFF) / 255
        )
    }
}

#if DEBUG
extension SupplyLevel {
    static let sampleBlack   = SupplyLevel(name: "Black",   percent: 50, color: Color(hex: "#000000"))
    static let sampleCyan    = SupplyLevel(name: "Cyan",    percent: 70, color: Color(hex: "#00CFFF"))
    static let sampleMagenta = SupplyLevel(name: "Magenta", percent: 60, color: Color(hex: "#F200FF"))
    static let sampleYellow  = SupplyLevel(name: "Yellow",  percent: 15, color: Color(hex: "#FFDA00"))
}
#endif
