import SwiftUI

struct PrinterPickerSidebar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List(selection: selectionBinding) {
            if appState.printers.isEmpty {
                emptyRow
            } else {
                ForEach(appState.printers) { printer in
                    PrinterRow(
                        printer: printer,
                        isSharing: appState.isSharingActive && printer == appState.selectedPrinter
                    )
                    .tag(Optional(printer))
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
    }

    private var selectionBinding: Binding<PrinterInfo?> {
        Binding(
            get: { appState.selectedPrinter },
            set: { appState.select($0) }
        )
    }

    private var emptyRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No printers detected.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Make sure they're connected to your Mac.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button {
                    appState.refreshPrinters()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }
}

private struct PrinterRow: View {
    let printer: PrinterInfo
    let isSharing: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "printer")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(printer.name)
                    .lineLimit(1)
                if !printer.model.isEmpty {
                    Text(printer.model)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Circle()
                .fill(isSharing ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 2)
    }
}

#if DEBUG
#Preview("With printers") {
    PrinterPickerSidebar()
        .environmentObject(AppState.previewSharing)
        .frame(width: 240, height: 400)
}

#Preview("Empty") {
    PrinterPickerSidebar()
        .environmentObject(AppState.previewEmpty)
        .frame(width: 240, height: 400)
}
#endif
