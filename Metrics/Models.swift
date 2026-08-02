import Foundation

nonisolated struct SystemSnapshot: Identifiable, Codable {
    var id = UUID()
    let timestamp: Date
    let cpuUsagePercent: Double
    let memUsedPercent: Double
    let memUsedBytes: UInt64
    let memTotalBytes: UInt64
    let gpuActivePercent: Double?
    let thermalPressure: String?
    let cpuTempC: Double?
    let gpuTempC: Double?
    let packagePowerWatts: Double?
}

nonisolated struct ProcessSnapshot: Identifiable, Codable, Equatable {
    var id = UUID()
    let timestamp: Date
    let pid: Int32
    let name: String
    let cpuPercent: Double
    let memBytes: UInt64
}

nonisolated struct ProcessAggregate: Identifiable {
    var id: String { name }
    let name: String
    let avgCPUPercent: Double
    let maxCPUPercent: Double
    let avgMemBytes: UInt64
    let maxMemBytes: UInt64
    let sampleCount: Int
}
