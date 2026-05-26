import SwiftUI

struct PrinterPickerSidebar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            if appState.printers.isEmpty {
                emptyState
            } else {
                printerList
            }
            Divider()
            footer
        }
    }

    private var printerList: some View {
        List(selection: selectionBinding) {
            ForEach(appState.printers) { printer in
                PrinterRow(
                    printer: printer,
                    isSharing: appState.isSharingActive && printer == appState.selectedPrinter
                )
                .tag(Optional(printer))
            }
        }
        .listStyle(.sidebar)
    }

    private var selectionBinding: Binding<PrinterInfo?> {
        Binding(
            get: { appState.selectedPrinter },
            set: { appState.select($0) }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "printer.dotmatrix")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No printers detected.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Make sure they're connected to your Mac.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal)
    }

    private var footer: some View {
        HStack {
            Button {
                appState.refreshPrinters()
            } label: {
                Image(systemName: "arrow.clockwise")
                Text("Refresh")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            Spacer()
        }
        .padding(8)
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
