import AppPresentation
import SwiftUI

struct RunTimelineView: View {
    @ObservedObject var model: TimelineUIModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Run timeline")
                .font(.title3)
            Text("Content-free log: action, target bundle id, result, time only.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.rows.isEmpty {
                Text("No events yet. Run a workflow from the menu bar.")
                    .accessibilityIdentifier("timeline.empty")
            } else {
                Table(model.rows) {
                    TableColumn("Time") { row in
                        Text(row.timeText)
                    }
                    TableColumn("Action") { row in
                        Text(row.actionKind)
                    }
                    TableColumn("Target") { row in
                        Text(row.targetBundleID)
                    }
                    TableColumn("Result") { row in
                        Text(row.result)
                    }
                }
                .accessibilityIdentifier("timeline.table")
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 320)
    }
}

struct TimelineRowUI: Identifiable {
    var id: String
    var timeText: String
    var actionKind: String
    var targetBundleID: String
    var result: String
}

@MainActor
final class TimelineUIModel: ObservableObject {
    @Published private(set) var rows: [TimelineRowUI] = []

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    func apply(_ viewModel: TimelineViewModel) {
        rows = viewModel.rows.map {
            TimelineRowUI(
                id: $0.id,
                timeText: formatter.string(from: $0.timestamp),
                actionKind: $0.actionKind,
                targetBundleID: $0.targetBundleID,
                result: $0.result
            )
        }
    }
}
