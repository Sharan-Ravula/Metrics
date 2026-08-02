import Foundation

/// Runs Apple's `powermetrics` as a long-lived background process and parses its
/// plist output stream to extract GPU activity and thermal info.
///
/// powermetrics requires root. See README.md for how to allow it to run
/// passwordless for your own user via sudoers, which this class expects.
/// If it's not configured, this sampler will simply report nil values and the
/// rest of the app keeps working with CPU/RAM/process data only.
nonisolated final class PowerMetricsSampler {

    struct Reading {
        let gpuActivePercent: Double?
        let thermalPressure: String?
        let cpuDieTempC: Double?
    }

    private var process: Process?
    private var buffer = Data()
    private let outputHandler: @MainActor (Reading) -> Void
    private let intervalMs: Int

    init(intervalMs: Int = 2000, onReading: @escaping @MainActor (Reading) -> Void) {
        self.intervalMs = intervalMs
        self.outputHandler = onReading
    }

    func start() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = [
            "-n", // non-interactive: fail instead of prompting, see README sudoers setup
            "/usr/bin/powermetrics",
            "-i", "\(intervalMs)",
            "--samplers", "gpu_power,thermal",
            "-f", "plist"
        ]

        let pipe = Pipe()
        task.standardOutput = pipe
        let errorPipe = Pipe()
        task.standardError = errorPipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            print("PowerMetricsSampler: received \(chunk.count) bytes")
            self?.handleIncoming(chunk)
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else { return }
            print("PowerMetricsSampler: STDERR: \(text)")
        }

        task.terminationHandler = { proc in
            print("PowerMetricsSampler: process exited with status \(proc.terminationStatus), reason \(proc.terminationReason)")
        }

        do {
            try task.run()
            self.process = task
            print("PowerMetricsSampler: launched powermetrics, pid \(task.processIdentifier)")
        } catch {
            print("PowerMetricsSampler: failed to launch powermetrics: \(error)")
        }
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    private func handleIncoming(_ chunk: Data) {
        buffer.append(chunk)
        while let nulRange = buffer.range(of: Data([0x00])) {
            let plistData = buffer.subdata(in: buffer.startIndex..<nulRange.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<nulRange.upperBound)
            parsePlist(plistData)
        }
    }

    private func parsePlist(_ data: Data) {
        guard !data.isEmpty,
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return }

        // GPU: the field names powermetrics actually emits vary by macOS
        // version/chip. Confirmed present on this Mac's real output: "idle_ratio"
        // (fraction of the sample the GPU was idle — active% = 1 - idle_ratio).
        // Older/other versions may instead expose "gpu_active_residency"
        // directly, so that's kept as a fallback.
        var gpuPercent: Double? = nil
        if let gpu = plist["gpu"] as? [String: Any] {
            if let idleRatio = gpu["idle_ratio"] as? Double {
                gpuPercent = (1 - idleRatio) * 100
            } else if let v = gpu["gpu_active_residency"] as? Double {
                gpuPercent = v
            } else if let s = gpu["gpu_active_residency"] as? String {
                gpuPercent = Double(s.replacingOccurrences(of: "%", with: ""))
            } else if let v = gpu["active_residency"] as? Double {
                gpuPercent = v
            }
        }

        var pressure: String? = nil
        if let thermal = plist["thermal_pressure"] as? String {
            pressure = thermal
        } else if let thermal = plist["thermal"] as? [String: Any],
                  let level = thermal["thermal_pressure"] as? String {
            pressure = level
        }

        var tempC: Double? = nil
        if let thermal = plist["thermal"] as? [String: Any],
           let temp = thermal["die_temperature"] as? Double {
            tempC = temp
        }

        let reading = Reading(gpuActivePercent: gpuPercent, thermalPressure: pressure, cpuDieTempC: tempC)
        let gpuText = gpuPercent.map { "\($0)" } ?? "nil"
        print("PowerMetricsSampler: parsed sample — gpu=\(gpuText), thermal=\(pressure ?? "nil")")
        Task { @MainActor [weak self] in
            self?.outputHandler(reading)
        }
    }
}
