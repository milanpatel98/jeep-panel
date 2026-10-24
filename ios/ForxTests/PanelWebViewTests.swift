import Foundation
import Testing
@testable import Forx

struct PanelWebViewTests {
    private func url(_ s: String) -> URL { URL(string: s)! }

    @Test func mimeTypes() {
        #expect(WebFiles.mimeType(forPath: "index.html") == "text/html")
        #expect(WebFiles.mimeType(forPath: "assets/index-abc.js") == "text/javascript")
        #expect(WebFiles.mimeType(forPath: "assets/index-abc.css") == "text/css")
        #expect(WebFiles.mimeType(forPath: "model/jeep.glb") == "model/gltf-binary")
        #expect(WebFiles.mimeType(forPath: "icons/i.svg") == "image/svg+xml")
        #expect(WebFiles.mimeType(forPath: "icons/icon-192.png") == "image/png")
        #expect(WebFiles.mimeType(forPath: "data.json") == "application/json")
        #expect(WebFiles.mimeType(forPath: "manifest.webmanifest") == "application/manifest+json")
        #expect(WebFiles.mimeType(forPath: "ICON.PNG") == "image/png")
        #expect(WebFiles.mimeType(forPath: "blob.bin") == "application/octet-stream")
    }

    @Test func mapsRequestPaths() {
        #expect(WebFiles.relativePath(for: WebFiles.startURL) == "index.html")
        #expect(WebFiles.relativePath(for: url("forx://app/")) == "index.html")
        #expect(WebFiles.relativePath(for: url("forx://app/assets/index-abc.js?v=1#x")) == "assets/index-abc.js")
        #expect(WebFiles.relativePath(for: url("forx://app/model/jeep.glb")) == "model/jeep.glb")
    }

    @Test func rejectsTraversal() throws {
        #expect(WebFiles.relativePath(for: url("forx://app/%2E%2E/secret.txt")) == nil)
        #expect(WebFiles.relativePath(for: url("forx://app/assets/%2e%2e/%2e%2e/secret.txt")) == nil)
        #expect(WebFiles.relativePath(for: url("forx://app/a%5C..%5Csecret.txt")) == nil)  // backslashes
        #expect(WebFiles.relativePath(for: url("file:///etc/passwd")) == nil)
        #expect(WebFiles.relativePath(for: url("forx://other/index.html")) == nil)

        // On disk: only regular files inside the root, symlinks resolved.
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("PanelWebViewTests-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("Web", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("assets", isDirectory: true), withIntermediateDirectories: true)
        try Data("<html></html>".utf8).write(to: root.appendingPathComponent("index.html"))
        try Data("secret".utf8).write(to: base.appendingPathComponent("secret.txt"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("escape.txt"),
            withDestinationURL: base.appendingPathComponent("secret.txt"))
        defer { try? FileManager.default.removeItem(at: base) }

        let index = WebFiles.fileURL(for: url("forx://app/index.html"), root: root)
        #expect(index?.lastPathComponent == "index.html")
        #expect(WebFiles.fileURL(for: url("forx://app/missing.js"), root: root) == nil)  // 404
        #expect(WebFiles.fileURL(for: url("forx://app/assets"), root: root) == nil)  // a folder
        #expect(WebFiles.fileURL(for: url("forx://app/../secret.txt"), root: root) == nil)
        #expect(WebFiles.fileURL(for: url("forx://app/assets/../../secret.txt"), root: root) == nil)
        #expect(WebFiles.fileURL(for: url("forx://app/%2E%2E/secret.txt"), root: root) == nil)
        #expect(WebFiles.fileURL(for: url("forx://app/escape.txt"), root: root) == nil)  // symlink out
    }

    @Test func mapsMessages() {
        #expect(panelMessage(["type": "ready"]) == .ready)
        #expect(panelMessage(["type": "settings"]) == .settings)
        let actions: [String: JeepCommand] = [
            "lock": .lock, "unlock": .unlock, "climateOn": .climateOn, "climateOff": .climateOff,
            "lights": .lights, "horn": .horn, "gate": .gate,
        ]
        for (action, cmd) in actions {
            #expect(panelMessage(["type": "command", "action": action]) == .command(cmd))
        }
        #expect(panelMessage(["type": "command", "action": "RDU"]) == nil)
        #expect(panelMessage(["type": "command"]) == nil)
        #expect(panelMessage(["type": "somethingNew"]) == nil)
        #expect(panelMessage("ready") == nil)
    }
}
