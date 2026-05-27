import SwiftUI

struct SettingsView: View {
    @AppStorage("autoConnect") private var autoConnect: Bool = true

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $autoConnect) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-connect on launch")
                        Text("Automatically start sharing when the previously selected printer is available.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 130)
    }
}

#if DEBUG
#Preview {
    SettingsView()
}
#endif
