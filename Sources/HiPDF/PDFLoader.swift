import Foundation
import PDFKit
import Darwin

struct PDFLoadFailure: LocalizedError {
    enum Kind: String { case unavailable, unreadable, invalid, password, timeout }
    let kind: Kind
    let message: String
    var errorDescription: String? { message }
    var title: String {
        switch kind {
        case .unavailable: return "云盘文件尚未就绪"
        case .unreadable: return "无法读取文件"
        case .invalid: return "无法解析此 PDF"
        case .password: return "文件需要密码"
        case .timeout: return "文件读取超时"
        }
    }
}

// The document is created on the reader queue, then transferred to the main actor.
// The reader never accesses it again after completing the continuation.
struct LoadedPDF: @unchecked Sendable { let document: PDFDocument }

enum PDFLoader {
    static func load(_ url: URL, password: String, timeout: TimeInterval = 30) async throws -> LoadedPDF {
        let operation = PDFReadOperation(url: url, password: password, timeout: timeout)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { operation.start($0) }
        } onCancel: { operation.cancel() }
    }

    static func isPlaceholder(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_flags & UInt32(SF_DATALESS) != 0
    }
}

private final class PDFReadOperation: @unchecked Sendable {
    private let url: URL
    private let password: String
    private let timeout: TimeInterval
    private let coordinator = NSFileCoordinator(filePresenter: nil)
    private let lock = NSLock()
    private var continuation: CheckedContinuation<LoadedPDF, Error>?
    private var outcome: Result<LoadedPDF, Error>?

    init(url: URL, password: String, timeout: TimeInterval) {
        self.url = url; self.password = password; self.timeout = timeout
    }

    func start(_ continuation: CheckedContinuation<LoadedPDF, Error>) {
        lock.lock()
        if let outcome { lock.unlock(); continuation.resume(with: outcome); return }
        self.continuation = continuation
        lock.unlock()
        DispatchQueue.global(qos: .userInitiated).async { self.read() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self else { return }
            self.finish(.failure(PDFLoadFailure(kind: .timeout, message: "读取文件超时。若文件位于云盘，请先在 Finder 中完成下载并恢复同步，再点击重新加载。")))
        }
    }

    func cancel() { finish(.failure(CancellationError())) }

    private func finish(_ result: Result<LoadedPDF, Error>) {
        lock.lock()
        guard outcome == nil else { lock.unlock(); return }
        outcome = result
        let callback = continuation; continuation = nil
        lock.unlock()
        coordinator.cancel()
        callback?.resume(with: result)
    }

    private func read() {
        guard lock.withLock({ outcome == nil }) else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let placeholder = PDFLoader.isPlaceholder(url)
        var coordinationError: NSError?
        var readResult: Result<LoadedPDF, Error>?
        // Coordinate with File Provider before reading; PDFKit's URL initializer
        // only returns nil on failure and hides download/permission errors.
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { readableURL in
            readResult = Result {
                let data: Data
                do { data = try Data(contentsOf: readableURL, options: .uncached) }
                catch { throw self.readFailure(error, placeholder: placeholder) }
                guard !data.isEmpty, let document = PDFDocument(data: data) else {
                    throw PDFLoadFailure(kind: .invalid, message: "已读到文件，但内容不是可解析的 PDF，或文件不完整。请用 macOS 预览检查这份文件。")
                }
                if document.isLocked && !document.unlock(withPassword: self.password) {
                    throw PDFLoadFailure(kind: .password, message: self.password.isEmpty ? "此 PDF 已加密，请在右侧填写文件打开密码。" : "文件打开密码不正确，请重新输入。")
                }
                guard document.pageCount > 0 else {
                    throw PDFLoadFailure(kind: .invalid, message: "PDF 中没有可预览的页面。")
                }
                return LoadedPDF(document: document)
            }
        }
        if let coordinationError { finish(.failure(readFailure(coordinationError, placeholder: placeholder))) }
        else if let readResult { finish(readResult) }
        else { finish(.failure(PDFLoadFailure(kind: .unreadable, message: "系统没有返回文件内容，请重新选择文件。"))) }
    }

    private func readFailure(_ error: Error, placeholder: Bool) -> PDFLoadFailure {
        if placeholder || PDFLoader.isPlaceholder(url) {
            return PDFLoadFailure(kind: .unavailable, message: "此文件目前是云盘占位文件，内容尚未能从云盘读取。请在 Finder 中下载文件；若 OneDrive 提示需要重启，请先恢复同步，然后点击重新加载。")
        }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoSuchFileError || ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOENT) {
            return PDFLoadFailure(kind: .unreadable, message: "文件已被移动或删除，请重新选择。")
        }
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoPermissionError || ns.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(ns.code) {
            return PDFLoadFailure(kind: .unreadable, message: "macOS 拒绝读取此文件，请检查文件访问权限，或通过“添加文件”重新选择。")
        }
        return PDFLoadFailure(kind: .unreadable, message: "文件内容读取失败（\(ns.domain)：\(ns.code)）。若位于云盘，请确认已经下载到本机后重试。")
    }
}
