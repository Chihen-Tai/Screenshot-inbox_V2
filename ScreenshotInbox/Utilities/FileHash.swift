import Foundation
import CryptoKit

/// SHA-256 hashing for files, used by `ImportService` to dedupe screenshots
/// across imports. Streamed via `FileHandle.read(upToCount:)` so very large
/// files don't pin memory.
enum FileHash {
    /// 64-char lowercase hex SHA-256 of the file at `url`. Throws if the file
    /// cannot be opened or read.
    static func sha256Hex(of url: URL, chunkSize: Int = 1 << 16) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: chunkSize)
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
