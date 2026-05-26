import SwiftUI

struct PrinterDetailView: View {
    @EnvironmentObject private var appState: AppState

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

            Toggle("Share this Printer", isOn: sharingBinding)
                .toggleStyle(.switch)
                .font(.headline)

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
            Text("Shared as: \"\(printer.name) (Inkognito)\"")
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
                HStack {
                    Spacer()
                    Button("Clear Jobs") { appState.clearJobs() }
                        .controlSize(.small)
                }
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

private struct JobRow: View {
    let job: PrintJob

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            Text(Self.timeFormatter.string(from: job.timestamp))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(job.sourceDevice ?? "Unknown")
                .font(.callout)
                .frame(minWidth: 60, alignment: .leading)
            Text(pagesLabel)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            statusBadge
        }
    }

    private var pagesLabel: String {
        guard let count = job.pageCount else { return "—" }
        return count == 1 ? "1 page" : "\(count) pages"
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
#endif
