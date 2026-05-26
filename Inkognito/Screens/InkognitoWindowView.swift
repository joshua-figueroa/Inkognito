import SwiftUI

struct InkognitoWindowView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showHelp = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            PrinterPickerSidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            PrinterDetailView()
                .navigationTitle("Inkognito")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showHelp.toggle()
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        .popover(isPresented: $showHelp, arrowEdge: .bottom) {
                            helpPopover
                        }
                        .help("About Inkognito")
                    }
                }
        }
        .navigationSplitViewStyle(.prominentDetail)
        .frame(minWidth: 700, idealWidth: 820, minHeight: 460, idealHeight: 500)
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
        .frame(width: 820, height: 500)
}

#Preview("No printers") {
    InkognitoWindowView()
        .environmentObject(AppState.previewEmpty)
        .frame(width: 820, height: 500)
}
#endif
