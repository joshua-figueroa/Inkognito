import SwiftUI

struct InkognitoWindowView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showHelp = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            PrinterPickerSidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            VStack(spacing: 0) {
                detailHeader
                Divider()
                PrinterDetailView()
            }
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 460, idealHeight: 500)
    }

    private var detailHeader: some View {
        HStack(spacing: 14) {
            Text("Inkognito")
                .font(.title3.weight(.semibold))
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    columnVisibility = (columnVisibility == .detailOnly) ? .all : .detailOnly
                }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.borderless)
            .help("Toggle sidebar")

            Button {
                showHelp.toggle()
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showHelp, arrowEdge: .bottom) {
                helpPopover
            }
            .help("About Inkognito")
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
    }

    private var helpPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your printer's secret identity.")
                .font(.headline)
            Text("Inkognito gives your dumb printer a secret AirPrint identity. Enable sharing, then pick this printer from any iPhone or iPad on your network.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 320)
    }
}

#if DEBUG
#Preview("Sharing with jobs") {
    InkognitoWindowView()
        .environmentObject(AppState.previewSharing)
}

#Preview("No printers") {
    InkognitoWindowView()
        .environmentObject(AppState.previewEmpty)
}
#endif
