import Foundation

struct HeaderImage {
    let url: URL
    let byteSize: Int64

    var name: String { url.lastPathComponent }

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteSize)
    }

    init?(url: URL) {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values?.fileSize, size > 0 else { return nil }
        self.url = url
        self.byteSize = Int64(size)
    }
}

enum PatchError: LocalizedError {
    case refusedInternalTarget
    case imageLargerThanTarget
    case authorizationFailed(String)
    case verificationMismatch

    var errorDescription: String? {
        switch self {
        case .refusedInternalTarget:
            return "Refused: the destination is not a removable external drive."
        case .imageLargerThanTarget:
            return "Refused: the image is larger than the destination drive."
        case .authorizationFailed(let detail):
            return detail
        case .verificationMismatch:
            return "The data read back does not match the image that was written."
        }
    }
}

/// Reads and writes the leading sectors of a drive.
///
/// Every write goes through an administrator prompt raised by the OS itself —
/// this process never handles the password. The destination is re-checked here
/// even though the UI already filtered it, because the cost of a wrong
/// destination is somebody's disk.
enum PatchWriter {
    /// Read-only capture of the leading sectors of a donor drive.
    static func capture(from drive: Drive, bytes: Int, to destination: URL) throws {
        let megabytes = max(1, bytes / (1024 * 1024))
        let command = """
            /bin/dd if=\(shellQuote(drive.rawDevicePath)) \
            of=\(shellQuote(destination.path)) bs=1m count=\(megabytes)
            """
        try runPrivileged(command, describedAs: "read the drive header")
    }

    static func write(image: HeaderImage, to drive: Drive) throws {
        guard drive.isRemovable else { throw PatchError.refusedInternalTarget }
        guard image.byteSize <= drive.byteSize else { throw PatchError.imageLargerThanTarget }

        let command = """
            /usr/sbin/diskutil unmountDisk \(shellQuote(drive.devicePath)) && \
            /bin/dd if=\(shellQuote(image.url.path)) \
            of=\(shellQuote(drive.rawDevicePath)) bs=1m
            """
        try runPrivileged(command, describedAs: "write the header to the drive")
    }

    // MARK: Privilege

    private static func runPrivileged(_ command: String, describedAs purpose: String) throws {
        // AppleScript raises the system authorization dialog. The password is
        // typed by the user into the OS panel; it never passes through here.
        let script = """
            do shell script "\(escapeForAppleScript(command))" with administrator privileges \
            with prompt "Sigil needs permission to \(purpose)."
            """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()

        try process.run()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let detail =
                String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "exit \(process.terminationStatus)"
            throw PatchError.authorizationFailed(detail)
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func escapeForAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
