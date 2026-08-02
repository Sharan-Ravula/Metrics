import SwiftUI
import Charts

enum ProcessViewMode: String, CaseIterable, Identifiable {
    case table = "Table"
    case bar = "Bar"
    case pie = "Pie"
    var id: String { rawValue }
}

struct ProcessListView: View {
    @EnvironmentObject var engine: MonitorEngine
    @ObservedObject var settings = SettingsStore.shared
    @State private var historyWindow = TimeWindow.oneHour

    private let reorderInterval: TimeInterval = 10

    @State private var liveOrder: [String] = []
    @State private var lastLiveReorder = Date.distantPast
    @State private var liveRows: [ProcessAggregate] = []

    @State private var historyOrder: [String] = []
    @State private var lastHistoryReorder = Date.distantPast
    @State private var historyRows: [ProcessAggregate] = []

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            liveSection
            offendersSection
        }
        .onAppear {
            updateLiveRows(engine.topProcesses)
            updateHistoryRows()
        }
        .onChange(of: engine.topProcesses) { _, newProcesses in
            updateLiveRows(newProcesses)
            updateHistoryRows()
        }
        .onChange(of: historyWindow) { _, _ in
            historyOrder = []
            updateHistoryRows()
        }
    }

    private var liveSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Live: What's Using CPU Right Now")
                .font(.title3.bold())
            Text("A snapshot as of the last refresh. Row order re-ranks every \(Int(reorderInterval))s so it doesn't jump around constantly.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                modePicker($settings.liveViewMode)
            }
            ProcessVisualization(rows: liveRows, mode: settings.liveViewMode, showMaxColumn: false)
            if liveRows.count > 15 {
                Text("Showing top 15 of \(liveRows.count) processes")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private var offendersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("History: What Used the Most Over Time")
                .font(.title3.bold())
            Text("Averages each app's CPU usage across the selected range — finds what hammered your Mac even after it's no longer running.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TimeWindowPicker(selection: $historyWindow, label: "Last")
                Spacer()
                modePicker($settings.historyViewMode)
            }

            if historyRows.isEmpty {
                Text("Not enough history yet for this range — check back in a bit, or pick a shorter window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                ProcessVisualization(rows: historyRows, mode: settings.historyViewMode, showMaxColumn: true)
                if historyRows.count > 15 {
                    Text("Showing top 15 of \(historyRows.count) processes")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func modePicker(_ selection: Binding<ProcessViewMode>) -> some View {
        Picker("View as", selection: selection) {
            ForEach(ProcessViewMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 180)
    }

    private func updateLiveRows(_ processes: [ProcessSnapshot]) {
        let now = Date()

        var merged: [String: (cpu: Double, mem: UInt64)] = [:]
        for p in processes {
            merged[p.name, default: (0, 0)].cpu += p.cpuPercent
            merged[p.name, default: (0, 0)].mem += p.memBytes
        }
        let current = merged.map { name, totals in
            ProcessAggregate(name: name, avgCPUPercent: totals.cpu, maxCPUPercent: totals.cpu,
                              avgMemBytes: totals.mem, maxMemBytes: totals.mem, sampleCount: 1)
        }
        let dict = Dictionary(current.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })

        if liveOrder.isEmpty || now.timeIntervalSince(lastLiveReorder) > reorderInterval {
            liveOrder = current.sorted { $0.avgCPUPercent > $1.avgCPUPercent }.map { $0.name }
            lastLiveReorder = now
        } else {
            for row in current where !liveOrder.contains(row.name) {
                liveOrder.append(row.name)
            }
        }
        liveRows = liveOrder.compactMap { dict[$0] }
    }

    private func updateHistoryRows() {
        let now = Date()
        let current = engine.history.topOffenders(window: historyWindow.seconds)
        let dict = Dictionary(current.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })

        if historyOrder.isEmpty || now.timeIntervalSince(lastHistoryReorder) > reorderInterval {
            historyOrder = current.sorted { $0.avgCPUPercent > $1.avgCPUPercent }.map { $0.name }
            lastHistoryReorder = now
        } else {
            for row in current where !historyOrder.contains(row.name) {
                historyOrder.append(row.name)
            }
        }
        historyRows = historyOrder.compactMap { dict[$0] }
    }
}

struct ProcessVisualization: View {
    let rows: [ProcessAggregate]
    let mode: ProcessViewMode
    var showMaxColumn: Bool = true

    @State private var hoveredSlice: (name: String, value: Double)?

    var body: some View {
        switch mode {
        case .table: tableView
        case .bar: barView
        case .pie: pieView
        }
    }

    private var tableView: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
            GridRow {
                Text("#").font(.caption).foregroundStyle(.secondary).frame(width: 20, alignment: .trailing)
                Text("App").font(.caption).foregroundStyle(.secondary).frame(width: 160, alignment: .leading)
                Text("Avg CPU").font(.caption).foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
                if showMaxColumn {
                    Text("Max CPU").font(.caption).foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
                }
                Text("Avg Mem").font(.caption).foregroundStyle(.secondary).frame(width: 72, alignment: .trailing)
            }
            Divider()
            ForEach(Array(rows.prefix(15).enumerated()), id: \.element.id) { index, row in
                GridRow {
                    Text("\(index + 1)").foregroundStyle(.secondary).frame(width: 20, alignment: .trailing)
                    HStack(spacing: 6) {
                        Image(nsImage: AppIconProvider.shared.icon(for: row.name))
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(row.name).lineLimit(1)
                    }
                    .frame(width: 160, alignment: .leading)
                    Text("\(row.avgCPUPercent, specifier: "%.1f")%")
                        .foregroundStyle(Severity.color(forPercent: row.avgCPUPercent))
                        .frame(width: 64, alignment: .trailing)
                    if showMaxColumn {
                        Text("\(row.maxCPUPercent, specifier: "%.1f")%")
                            .foregroundStyle(Severity.color(forPercent: row.maxCPUPercent))
                            .frame(width: 64, alignment: .trailing)
                    }
                    Text(formatBytes(row.avgMemBytes))
                        .foregroundStyle(Severity.color(forBytes: row.avgMemBytes))
                        .frame(width: 72, alignment: .trailing)
                }
                .font(.system(size: 13, design: .monospaced))
            }
        }
    }

    private var barView: some View {
        let top = Array(rows.sorted { $0.avgCPUPercent > $1.avgCPUPercent }.prefix(10))
        return Chart(top) { row in
            BarMark(
                x: .value("Avg CPU %", row.avgCPUPercent),
                y: .value("App", row.name)
            )
            .foregroundStyle(Severity.color(forPercent: row.avgCPUPercent))
            .annotation(position: .trailing) {
                Text("\(row.avgCPUPercent, specifier: "%.0f")%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))%")
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: CGFloat(top.count) * 28 + 20)
    }

    private var pieSlices: [(name: String, value: Double)] {
        let top = rows.sorted { $0.avgCPUPercent > $1.avgCPUPercent }.prefix(6)
        let topTotal = top.reduce(0.0) { $0 + $1.avgCPUPercent }
        let allTotal = rows.reduce(0.0) { $0 + $1.avgCPUPercent }
        var slices = top.map { (name: $0.name, value: $0.avgCPUPercent) }
        let remainder = allTotal - topTotal
        if remainder > 0.5 {
            slices.append((name: "Other", value: remainder))
        }
        return slices
    }

    private var pieView: some View {
        let slices = pieSlices
        let total = slices.reduce(0.0) { $0 + $1.value }
        return Chart(slices, id: \.name) { slice in
            SectorMark(angle: .value("CPU", slice.value), innerRadius: .ratio(0.55), angularInset: 1.5)
                .foregroundStyle(by: .value("App", slice.name))
                .cornerRadius(3)
                .opacity(hoveredSlice == nil || hoveredSlice?.name == slice.name ? 1 : 0.35)
        }
        .chartLegend(position: .bottom, alignment: .leading, spacing: 4)
        .frame(height: 260)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plotFrame = proxy.plotFrame, total > 0 else {
                                hoveredSlice = nil
                                return
                            }
                            let rect = geo[plotFrame]
                            let center = CGPoint(x: rect.midX, y: rect.midY)
                            let outerRadius = min(rect.width, rect.height) / 2
                            let innerRadius = outerRadius * 0.55
                            let dx = location.x - center.x
                            let dy = location.y - center.y
                            let distance = (dx * dx + dy * dy).squareRoot()
                            guard distance <= outerRadius, distance >= innerRadius else {
                                hoveredSlice = nil
                                return
                            }
                            var angle = atan2(dy, dx) + .pi / 2
                            if angle < 0 { angle += 2 * .pi }
                            let value = (angle / (2 * .pi)) * total
                            var cumulative = 0.0
                            hoveredSlice = slices.first { slice in
                                cumulative += slice.value
                                return value <= cumulative
                            } ?? slices.last
                        case .ended:
                            hoveredSlice = nil
                        }
                    }
            }
        }
        .overlay(alignment: .top) {
            if let hoveredSlice {
                Text("\(hoveredSlice.name): \(hoveredSlice.value, specifier: "%.1f")% CPU")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 4)
            } else {
                Text("Hover a slice to see details")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}
