import Foundation

/// The last snapshot on disk, so the panel shows something when the Jeep or the
/// network can't be reached.
nonisolated struct SnapshotCache: Sendable {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    func save(_ s: JeepSnapshot) throws {
        let data = try JSONEncoder().encode(s)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func load() -> JeepSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(JeepSnapshot.self, from: data)
    }
}
