import Foundation

struct Drive: Identifiable, Hashable {
    let id: String        // BSD name, e.g. "disk4"
    let name: String      // Marketing name reported by the device
    let byteSize: Int64
    let isRemovable: Bool

    var devicePath: String { "/dev/\(id)" }
    var rawDevicePath: String { "/dev/r\(id)" }

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useTB]
        return formatter.string(fromByteCount: byteSize)
    }
}

enum DriveScanError: Error {
    case diskutilFailed(String)
    case unreadableOutput
}

/// Enumerates attached drives. Read-only: it never opens a device for writing
/// and never shells out to anything that could modify one.
///
/// Internal and boot media are filtered out at the source by asking diskutil
/// for `external physical` only, and then checked a second time per device —
/// a wrong destination here destroys somebody's disk, so one filter is not
/// enough.
enum DriveScanner {
    static func scan() throws -> [Drive] {
        let listing = try runDiskutil(["list", "-plist", "external", "physical"])
        guard
            let root = try PropertyListSerialization.propertyList(
                from: listing, format: nil
            ) as? [String: Any],
            let wholeDisks = root["WholeDisks"] as? [String]
        else {
            throw DriveScanError.unreadableOutput
        }

        return try wholeDisks.compactMap { try describe(bsdName: $0) }
    }

    private static func describe(bsdName: String) throws -> Drive? {
        let info = try runDiskutil(["info", "-plist", bsdName])
        guard
            let device = try PropertyListSerialization.propertyList(
                from: info, format: nil
            ) as? [String: Any]
        else {
            return nil
        }

        // Second gate. `external physical` should already have excluded these,
        // but the cost of trusting it and being wrong is somebody's data.
        let isInternal = device["Internal"] as? Bool ?? true
        let isBoot = device["OSInternal"] as? Bool ?? false
        guard !isInternal, !isBoot else { return nil }

        let size = device["TotalSize"] as? Int64 ?? device["Size"] as? Int64 ?? 0
        guard size > 0 else { return nil }

        let name =
            device["MediaName"] as? String
            ?? device["IORegistryEntryName"] as? String
            ?? bsdName

        return Drive(
            id: bsdName,
            name: name.trimmingCharacters(in: .whitespaces),
            byteSize: size,
            isRemovable: device["Removable"] as? Bool ?? true
        )
    }

    private static func runDiskutil(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = arguments

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw DriveScanError.diskutilFailed(
                String(data: errorData, encoding: .utf8) ?? "exit \(process.terminationStatus)"
            )
        }
        return data
    }
}
