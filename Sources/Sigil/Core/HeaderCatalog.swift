import CryptoKit
import Foundation

/// One header image published by the project.
struct CatalogEntry: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let firmware: String
    let driveBytes: Int64?   // nil when the image is not tied to a capacity.
    let byteSize: Int64
    let sha256: String
    let url: URL

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteSize)
    }
}

private struct Manifest: Codable {
    let version: Int
    let headers: [CatalogEntry]
}

enum CatalogState {
    case loading
    case ready([CatalogEntry])
    case unreachable(String)
}

enum CatalogError: LocalizedError {
    case badResponse(Int)
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .badResponse(let code): return "GitHub answered \(code)."
        case .checksumMismatch:
            return "The downloaded file does not match its published checksum."
        }
    }
}

/// Fetches the published header images from the project's own repository, so
/// nobody has to go hunting for a file. Everything here degrades to the
/// bring-your-own-image path when the network or GitHub is not available.
enum HeaderCatalog {
    static let manifestURL = URL(
        string: "https://raw.githubusercontent.com/NspxMiguel/sigil/main/headers/manifest.json"
    )!

    static func load() async -> CatalogState {
        var request = URLRequest(url: manifestURL)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadRevalidatingCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .unreachable("No response from GitHub.")
            }
            guard http.statusCode == 200 else {
                return .unreachable(CatalogError.badResponse(http.statusCode).localizedDescription)
            }
            let manifest = try JSONDecoder().decode(Manifest.self, from: data)
            return .ready(manifest.headers)
        } catch {
            return .unreachable(error.localizedDescription)
        }
    }

    /// Downloads one entry and refuses to hand it back unless the checksum
    /// matches. This file gets written to a block device — a corrupted or
    /// swapped download is not something to discover afterwards.
    static func download(_ entry: CatalogEntry) async throws -> HeaderImage {
        let (temporary, response) = try await URLSession.shared.download(from: entry.url)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw CatalogError.badResponse(http.statusCode)
        }

        let data = try Data(contentsOf: temporary)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest.caseInsensitiveCompare(entry.sha256) == .orderedSame else {
            try? FileManager.default.removeItem(at: temporary)
            throw CatalogError.checksumMismatch
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(entry.id).img")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)

        guard let image = HeaderImage(url: destination) else {
            throw CatalogError.checksumMismatch
        }
        return image
    }
}
