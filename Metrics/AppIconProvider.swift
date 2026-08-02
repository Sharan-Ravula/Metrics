import AppKit
import UniformTypeIdentifiers

final class AppIconProvider {
    static let shared = AppIconProvider()

    private var cache: [String: NSImage] = [:]

    func icon(for processName: String) -> NSImage {
        if let cached = cache[processName] { return cached }
        let icon = lookupIcon(for: processName)
        cache[processName] = icon
        return icon
    }

    private func lookupIcon(for processName: String) -> NSImage {
        let apps = NSWorkspace.shared.runningApplications
        if let match = apps.first(where: { app in
            guard let name = app.localizedName, !name.isEmpty else { return false }
            return processName.hasPrefix(name) || name.hasPrefix(processName)
        }) {
            return match.icon ?? fallbackIcon
        }
        return fallbackIcon
    }

    private var fallbackIcon: NSImage {
        NSWorkspace.shared.icon(for: .unixExecutable)
    }
}
