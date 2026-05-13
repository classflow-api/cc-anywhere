// ImageDownloader.swift
// Downloads images posted by phones to the local inbox folder.
// See 需求规格说明书 §3.1 M7 (scene 2) + R-M7-04 / R-M7-07.

import Foundation
import CryptoKit

public actor ImageDownloader {
    public static let shared = ImageDownloader()

    private let log = AppLogger.shared.tagged("ImageDownloader")

    public static var inboxDir: URL {
        let base = PreferencesService.appSupportDir
            .appendingPathComponent("inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Download `url` into the local inbox; if `expectedSha256` is supplied,
    /// verifies and returns nil on mismatch.
    public func download(url: URL,
                         filename: String,
                         expectedSha256: String? = nil) async -> URL? {
        let target = Self.inboxDir.appendingPathComponent(filename)
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                log.error("download HTTP \(http.statusCode) for \(url.absoluteString)")
                return nil
            }
            if let expected = expectedSha256 {
                let got = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                if got.lowercased() != expected.lowercased() {
                    log.error("sha256 mismatch want=\(expected) got=\(got)")
                    return nil
                }
            }
            try data.write(to: target, options: .atomic)
            log.info("downloaded \(filename) (\(data.count) bytes)")
            return target
        } catch {
            log.error("download failed: \(error)")
            return nil
        }
    }

    /// Sweep inbox to remove files older than 7 days (R-M7-07).
    public func purgeOldFiles() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: Self.inboxDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        for url in urls {
            if let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
               mod < cutoff {
                try? fm.removeItem(at: url)
            }
        }
    }
}
