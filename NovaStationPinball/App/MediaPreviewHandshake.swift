import Foundation

enum MediaPreviewHandshakeError: Error {
    case cachesDirectoryUnavailable
    case timedOut(String)
}

/// App-local, token-scoped synchronization used only by the deterministic UI-test preview run.
@MainActor
struct MediaPreviewHandshake {
    private let token: String
    private let directory: URL

    init(token: String, fileManager: FileManager = .default) throws {
        guard token.range(of: #"\A[0-9a-f]{32}\z"#, options: .regularExpression) != nil,
              let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw MediaPreviewHandshakeError.cachesDirectoryUnavailable
        }
        self.token = token
        directory = caches
            .appendingPathComponent("NovaStationMediaHandshake", isDirectory: true)
            .appendingPathComponent(token, isDirectory: true)
    }

    func prepareAndSignalReady(fileManager: FileManager = .default) throws {
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try write("ready")
    }

    func waitForRecording(timeout: Duration = .seconds(30)) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if markerMatches("recording") { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw MediaPreviewHandshakeError.timedOut("recording")
    }

    func signalStarted() throws {
        try write("started")
    }

    func signalComplete() throws {
        try write("complete")
    }

    private func markerMatches(_ name: String) -> Bool {
        guard let data = try? Data(contentsOf: marker(name)),
              let value = String(data: data, encoding: .utf8) else { return false }
        return value == token
    }

    private func write(_ name: String) throws {
        try Data(token.utf8).write(to: marker(name), options: .atomic)
    }

    private func marker(_ name: String) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }
}
