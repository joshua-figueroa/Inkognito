import SwiftUI

struct PrinterDetailView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showSupply = false
    @State private var isHoveringInk = false

    var body: some View {
        Group {
            if let printer = appState.selectedPrinter {
                content(for: printer)
            } else {
                unselected
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func content(for printer: PrinterInfo) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(printer.model.isEmpty ? printer.name : printer.model)
                .font(.title2.weight(.semibold))

            Divider()

            statusSection(for: printer)

            HStack {
                Toggle("Share this Printer", isOn: sharingBinding)
                    .toggleStyle(.switch)
                    .font(.headline)
                Spacer()
                Button {
                    appState.refreshSupply()
                    showSupply = true
                } label: {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 35, height: 35)
                }
                .buttonStyle(.plain)
                .modifier(GlassCircleModifier())
                .brightness(isHoveringInk ? 0.05 : 0)
                .animation(.easeOut(duration: 0.1), value: isHoveringInk)
                .onHover { isHoveringInk = $0 }
                .popover(isPresented: $showSupply, arrowEdge: .leading) {
                    SupplyPopover()
                        .environmentObject(appState)
                }
                .help("Show Ink Levels")
            }

            Divider()

            Text("Recent Jobs")
                .font(.headline)

            jobsSection

            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private func statusSection(for printer: PrinterInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(appState.isSharingActive ? Color.green : Color.primary.opacity(0.5))
                    .frame(width: 10, height: 10)
                Text(appState.isSharingActive ? "Sharing as AirPrint" : "Not Sharing")
                    .font(.subheadline)
            }
            Text("Shared as: \"\(printer.displayName) (Inkognito)\"")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let error = appState.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var jobsSection: some View {
        Group {
            if appState.recentJobs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No jobs yet. Your printer is waiting for its first mission.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                List(displayedJobs) { job in
                    JobRow(job: job)
                }
                .listStyle(.inset)
                .frame(minHeight: 140)
            }
        }
    }

    private var displayedJobs: [PrintJob] {
        Array(appState.recentJobs.suffix(AppState.displayedJobsLimit).reversed())
    }

    private var sharingBinding: Binding<Bool> {
        Binding(
            get: { appState.isSharingActive },
            set: { newValue in
                if newValue {
                    appState.startSharing()
                } else {
                    appState.stopSharing()
                }
            }
        )
    }

    private var unselected: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "printer")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("Select a printer to begin")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Choose a printer from the sidebar, then flip the share switch to make it available to nearby iPhones and iPads.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct GlassCircleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(in: Circle())
        } else {
            content.background(.ultraThinMaterial, in: Circle())
        }
    }
}

private struct SupplyPopover: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ink Levels")
                .font(.headline)
            if appState.isLoadingSupply {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if appState.supplyLevels.isEmpty {
                Text("Unavailable")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appState.supplyLevels) { level in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(level.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(level.percent)%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: Double(level.percent), total: 100)
                            .tint(level.color)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 200)
    }
}

private struct JobRow: View {
    let job: PrintJob

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:mm"
        return f
    }()

    private var timestampLabel: String {
        if Calendar.current.isDateInToday(job.timestamp) {
            return Self.timeFormatter.string(from: job.timestamp)
        }
        if Calendar.current.isDateInYesterday(job.timestamp) {
            return "Yesterday \(Self.timeFormatter.string(from: job.timestamp))"
        }
        return Self.dateTimeFormatter.string(from: job.timestamp)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(timestampLabel)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(job.sourceDevice ?? "Unknown")
                    .font(.callout)
                if let name = job.documentName {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 80, alignment: .leading)
            Spacer()
            if let pages = job.pageCount {
                Text(pages == 1 ? "1 page" : "\(pages) pages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
            if let kb = job.sizeKB {
                Text(kb >= 1024 ? "\(kb / 1024) MB" : "\(kb) KB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }
            statusBadge
        }
    }

    private var statusBadge: some View {
        Group {
            switch job.status {
            case .pending:
                Label("Pending", systemImage: "hourglass")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            case .done:
                Label("Done", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
            case .failed:
                Label("Failed", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.red)
            }
        }
    }
}

#if DEBUG
#Preview("No selection") {
    PrinterDetailView()
        .environmentObject(AppState.previewEmpty)
        .frame(width: 480, height: 480)
}

#Preview("Selected, not sharing") {
    PrinterDetailView()
        .environmentObject(AppState.previewIdle)
        .frame(width: 480, height: 480)
}

#Preview("Sharing with mixed jobs") {
    PrinterDetailView()
        .environmentObject(AppState.previewSharing)
        .frame(width: 480, height: 480)
}

#Preview("Supply popover — loaded") {
    SupplyPopover()
        .environmentObject(AppState.previewSupplyLoaded)
}

#Preview("Supply popover — loading") {
    SupplyPopover()
        .environmentObject(AppState.previewSupplyLoading)
}

#Preview("Supply popover — unavailable") {
    SupplyPopover()
        .environmentObject(AppState.previewEmpty)
}
#endif
