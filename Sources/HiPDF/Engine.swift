import Foundation
import Security

struct EngineError: LocalizedError { var message: String; var errorDescription: String? { message } }

enum KeychainStore {
    static let service = "app.hipdf.mac.ai"
    static func read() -> String {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"api-key",kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary,&result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data:data,encoding:.utf8) ?? ""
    }
    static func save(_ key: String) throws {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"api-key"]
        if key.isEmpty { let status = SecItemDelete(query as CFDictionary); if status != errSecSuccess && status != errSecItemNotFound { throw EngineError(message:"无法清除钥匙串中的 API Key。") }; return }
        let update = [kSecValueData as String:Data(key.utf8)]
        var status = SecItemUpdate(query as CFDictionary,update as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = Data(key.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary,nil)
        }
        if status != errSecSuccess { throw EngineError(message:"无法保存 API Key 到 macOS 钥匙串（\(status)）。") }
    }
}

struct AIConfiguration: Codable {
    var baseURL = "https://api.openai.com/v1"
    var model = ""
    var timeout = "120"
    var maxTokens = "4096"
    var chunkSize = "7000"
    var sendTemperature = true
    var tokenParameter = "max_tokens"
    static func load() -> AIConfiguration { UserDefaults.standard.data(forKey:"aiConfiguration").flatMap { try? JSONDecoder().decode(Self.self,from:$0) } ?? Self() }
    func save() { if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data,forKey:"aiConfiguration") } }
    func dictionary(apiKey: String? = nil) -> [String:Any] {
        ["baseURL":baseURL,"model":model,"timeout":timeout,"maxTokens":maxTokens,"chunkSize":chunkSize,"sendTemperature":sendTemperature,"tokenParameter":tokenParameter,"apiKey":apiKey ?? KeychainStore.read()]
    }
}

final class EngineClient: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    func cancel() {
        lock.lock(); cancelled = true; let running = process; lock.unlock()
        guard let running, running.isRunning else { return }
        // Terminate descendants (LibreOffice/OCR) before the worker cleans its staging folder.
        let query = Process(); let pipe = Pipe()
        query.executableURL = URL(fileURLWithPath:"/bin/ps"); query.arguments = ["-axo","pid=,ppid="]; query.standardOutput = pipe
        if (try? query.run()) != nil {
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); query.waitUntilExit()
            let rows = String(data:data,encoding:.utf8)?.split(separator:"\n").compactMap { line -> (Int32,Int32)? in
                let parts = line.split(whereSeparator: { $0.isWhitespace }).compactMap { Int32($0) }; return parts.count == 2 ? (parts[0],parts[1]) : nil
            } ?? []
            var parents: Set<Int32> = [running.processIdentifier]
            for _ in 0..<8 { let next = Set(rows.filter { parents.contains($0.1) }.map(\.0)); let before = parents.count; parents.formUnion(next); if parents.count == before { break } }
            for pid in parents where pid != running.processIdentifier { Darwin.kill(pid,SIGTERM) }
        }
        running.terminate()
    }
    func run(_ request: [String:Any], progress: @escaping @Sendable (String,Double) -> Void = { _,_ in }) async throws -> [String:Any] {
        let payload = try JSONSerialization.data(withJSONObject:request)
        lock.withLock { cancelled = false }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos:.userInitiated).async {
                let child = Process(); let input = Pipe(); let output = Pipe(); let errors = Pipe()
                let root = ResourceLocation.root
                let bundled = root.appendingPathComponent("python/bin/python3")
                let python = FileManager.default.fileExists(atPath:bundled.path) ? bundled : ResourceLocation.project.appendingPathComponent(".venv/bin/python")
                let bundledWorker = root.appendingPathComponent("engine/worker.py")
                let worker = FileManager.default.fileExists(atPath:bundledWorker.path) ? bundledWorker : ResourceLocation.project.appendingPathComponent("engine/worker.py")
                child.executableURL = python; child.arguments = ["-u",worker.path]
                child.standardInput = input; child.standardOutput = output; child.standardError = errors
                var environment = ProcessInfo.processInfo.environment
                environment["PYTHONUNBUFFERED"] = "1"; environment["PYTHONNOUSERSITE"] = "1"; environment["PYTHONDONTWRITEBYTECODE"] = "1"
                environment.removeValue(forKey:"PYTHONPATH"); environment.removeValue(forKey:"PYTHONHOME")
                child.environment = environment
                errors.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
                var result: [String:Any]?
                var buffer = Data()
                do {
                    self.lock.lock(); self.process = child; let wasCancelled = self.cancelled; self.lock.unlock()
                    if wasCancelled { throw EngineError(message:"任务已取消。") }
                    try child.run()
                    if self.lock.withLock({ self.cancelled }) { child.terminate() }
                    try input.fileHandleForWriting.write(contentsOf:payload)
                    try input.fileHandleForWriting.close()
                    while let data = try output.fileHandleForReading.read(upToCount:4096), !data.isEmpty {
                        buffer.append(data)
                        while let newline = buffer.firstIndex(of:10) {
                            let line = buffer.prefix(upTo:newline); buffer.removeSubrange(...newline)
                            if let event = try? JSONSerialization.jsonObject(with:line) as? [String:Any] {
                                if event["type"] as? String == "progress" { progress(event["message"] as? String ?? "正在处理",event["progress"] as? Double ?? 0) }
                                if event["type"] as? String == "result" { result = event }
                            }
                        }
                    }
                    child.waitUntilExit()
                    errors.fileHandleForReading.readabilityHandler = nil
                    self.lock.lock(); self.process = nil; let cancelledAtEnd = self.cancelled; self.lock.unlock()
                    if cancelledAtEnd { throw EngineError(message:"任务已取消。") }
                    guard let result else { throw EngineError(message:"本地引擎意外退出，请检查应用是否完整。") }
                    guard result["ok"] as? Bool == true else { throw EngineError(message:result["error"] as? String ?? "文件处理失败。") }
                    continuation.resume(returning:result)
                } catch {
                    errors.fileHandleForReading.readabilityHandler = nil
                    if child.isRunning { child.terminate() }
                    self.lock.lock(); self.process = nil; self.lock.unlock()
                    continuation.resume(throwing:error)
                }
            }
        }
    }
}
