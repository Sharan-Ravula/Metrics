import Foundation
import SoCMetrics

/// Reads real CPU/GPU die temperature and package power on Apple Silicon,
/// sudoless, via the swift-soc-metrics package.
///
/// `sampleOnce(window:)` blocks for the given window while it measures — call
/// it once per refresh tick from a background task, not in a free-running
/// loop. (An earlier version of this class ran its own continuous 0.5s loop
/// independent of the app's refresh rate setting, which meant temperature
/// sampling never actually slowed down even if you set a long refresh
/// interval to save battery. This version samples exactly once per tick,
/// so it scales with whatever rate you've chosen.)
nonisolated final class SoCTemperatureReader {

    struct Reading {
        let cpuTempC: Double?
        let gpuTempC: Double?
        let packagePowerWatts: Double?
    }

    private var sampler: SoCSampler?
    private(set) var isAvailable = false

    /// Creates the underlying sampler. Fast, no blocking — safe to call on
    /// the main actor.
    func start() {
        do {
            sampler = try SoCSampler()
            isAvailable = true
        } catch {
            print("SoCTemperatureReader: unavailable on this Mac — \(error)")
            isAvailable = false
        }
    }

    func stop() {
        sampler = nil
    }

    /// Blocks for `window` seconds. Call this off the main actor.
    func sampleOnce(window: TimeInterval = 0.3) -> Reading {
        guard let sampler else {
            return Reading(cpuTempC: nil, gpuTempC: nil, packagePowerWatts: nil)
        }
        let s = sampler.sample(interval: window)
        return Reading(cpuTempC: s.cpuTemperatureC, gpuTempC: s.gpuTemperatureC, packagePowerWatts: s.packagePowerWatts)
    }
}
