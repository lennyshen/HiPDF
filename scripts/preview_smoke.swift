// Run with: swiftc -parse-as-library Sources/HiPDF/PDFLoader.swift scripts/preview_smoke.swift -o /tmp/hipdf-preview-tests && /tmp/hipdf-preview-tests
import Foundation
import PDFKit

@main struct PreviewSmoke {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "HiPDF.PreviewTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func expect(_ kind: PDFLoadFailure.Kind, url: URL, password: String = "") async throws {
        do { _ = try await PDFLoader.load(url, password: password); try require(false, "Expected \(kind) for \(url.lastPathComponent)") }
        catch let error as PDFLoadFailure { try require(error.kind == kind, "Expected \(kind), got \(error.kind)") }
    }
    static func fixture() -> Data {
        let stream = "BT /F1 18 Tf 30 300 Td (HiPDF Preview 158000) Tj ET\n"
        let objects = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>", "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>", "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>", "<< /Length \(stream.utf8.count) >>\nstream\n\(stream)endstream"]
        var pdf = "%PDF-1.7\n", offsets: [Int] = []
        for (index, object) in objects.enumerated() { offsets.append(pdf.utf8.count); pdf += "\(index+1) 0 obj\n\(object)\nendobj\n" }
        let xref = pdf.utf8.count
        pdf += "xref\n0 6\n0000000000 65535 f \n"
        for offset in offsets { pdf += String(format: "%010d 00000 n \n", offset) }
        pdf += "trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(pdf.utf8)
    }
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hipdf-preview-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("中文 空格.PDF"), invalid = root.appendingPathComponent("invalid.pdf"), empty = root.appendingPathComponent("empty.pdf"), locked = root.appendingPathComponent("locked.pdf")
        let bytes = fixture(); try bytes.write(to: source)
        try Data("not a PDF".utf8).write(to: invalid); try Data().write(to: empty)
        let loaded = try await PDFLoader.load(source, password: "")
        try require(loaded.document.pageCount == 1 && loaded.document.string?.contains("158000") == true, "Normal PDF failed to load")
        try require(loaded.document.write(to: locked, withOptions: [.userPasswordOption: "preview-test", .ownerPasswordOption: "owner-test"]), "Encrypted fixture could not be written")
        try await expect(.password, url: locked)
        try await expect(.password, url: locked, password: "wrong")
        let unlocked = try await PDFLoader.load(locked, password: "preview-test")
        try require(!unlocked.document.isLocked && unlocked.document.pageCount == 1, "Correct password failed")
        try await expect(.invalid, url: invalid)
        try await expect(.invalid, url: empty)
        try await expect(.unreadable, url: root.appendingPathComponent("missing.pdf"))
        let cancelled = Task { try await PDFLoader.load(source, password: "") }
        cancelled.cancel()
        do { _ = try await cancelled.value; try require(false, "Cancellation did not cancel the load") }
        catch is CancellationError { }
        try require(try Data(contentsOf: source) == bytes, "Preview modified the original file")
        print("PASS: local Unicode path, text/page rendering data, empty/invalid/missing files, missing/wrong/correct password, cancellation, original bytes unchanged")
        if CommandLine.arguments.count > 1 {
            let cloud = URL(fileURLWithPath: CommandLine.arguments[1])
            guard PDFLoader.isPlaceholder(cloud) else { print("Cloud fixture is already local; no unavailable-provider check needed"); return }
            let started = Date()
            do { _ = try await PDFLoader.load(cloud, password: "", timeout: 3); print("Cloud provider successfully downloaded the fixture") }
            catch let error as PDFLoadFailure {
                try require([.unavailable, .timeout].contains(error.kind), "Cloud read failure was misreported as a PDF/password problem")
                try require(Date().timeIntervalSince(started) < 5, "Cloud request was not bounded")
                print("PASS: actual cloud placeholder reports \(error.kind) within bounded time")
            }
        }
    }
}
