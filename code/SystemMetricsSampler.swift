import Foundation
import Darwin

/// Reads system-wide CPU and memory usage using low-level Mach host APIs.
/// No special entitlements or sudo required.
final class SystemMetricsSampler {

    // Keep previous CPU tick counts so we can compute a delta-based percentage
    // rather than a cumulative-since-boot one.
    private var prevCPUTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?

    /// Returns (usedPercent, usedBytes, totalBytes)
    func sampleMemory() -> (percent: Double, used: UInt64, total: UInt64) {
        var totalBytes: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &totalBytes, &size, nil, 0)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return (0, 0, totalBytes)
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        // "Used" here mirrors Activity Monitor's memory pressure notion reasonably well:
        // active + wired + compressed pages, excluding free/inactive/purgeable.
        let used = active + wired + compressed
        let percent = totalBytes > 0 ? (Double(used) / Double(totalBytes)) * 100.0 : 0
        return (percent, used, totalBytes)
    }

    /// Returns overall CPU usage percent (0-100) across all cores, computed from
    /// the delta between this call and the previous one.
    func sampleCPU() -> Double {
        var cpuCount: natural_t = 0
        var cpuInfo: processor_info_array_t!
        var numCpuInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(),
                                          PROCESSOR_CPU_LOAD_INFO,
                                          &cpuCount,
                                          &cpuInfo,
                                          &numCpuInfo)
        guard result == KERN_SUCCESS else { return 0 }

        defer {
            let size = vm_size_t(Int(numCpuInfo) * MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)
        }

        var totalUser: UInt32 = 0
        var totalSystem: UInt32 = 0
        var totalIdle: UInt32 = 0
        var totalNice: UInt32 = 0

        for i in 0..<Int(cpuCount) {
            let offset = Int(CPU_STATE_MAX) * i
            totalUser += UInt32(cpuInfo[offset + Int(CPU_STATE_USER)])
            totalSystem += UInt32(cpuInfo[offset + Int(CPU_STATE_SYSTEM)])
            totalIdle += UInt32(cpuInfo[offset + Int(CPU_STATE_IDLE)])
            totalNice += UInt32(cpuInfo[offset + Int(CPU_STATE_NICE)])
        }

        defer {
            prevCPUTicks = (totalUser, totalSystem, totalIdle, totalNice)
        }

        guard let prev = prevCPUTicks else { return 0 }

        let userDiff = Double(totalUser &- prev.user)
        let systemDiff = Double(totalSystem &- prev.system)
        let idleDiff = Double(totalIdle &- prev.idle)
        let niceDiff = Double(totalNice &- prev.nice)
        let totalDiff = userDiff + systemDiff + idleDiff + niceDiff

        guard totalDiff > 0 else { return 0 }
        let busy = userDiff + systemDiff + niceDiff
        return (busy / totalDiff) * 100.0
    }
}
