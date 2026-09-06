// Integration harness for the actual Swift -> bundled Python bridge; no UI automation.
import Foundation
import PDFKit
@main struct BridgeSmoke {
    static func main() async throws {
        guard CommandLine.arguments.count == 3 else {fatalError("source.pdf output-directory")}
        let source = CommandLine.arguments[1],output = CommandLine.arguments[2]
        let engine = EngineClient()
        let health = try await engine.run(["action":"health"])
        guard health["office"] as? Bool == true,health["ocr"] as? Bool == true else {throw EngineError(message:"Bundled dependency unavailable")}
        let result = try await engine.run(["action":"compress","files":[source],"outputDir":output,"options":["compression":"balanced"]])
        guard let outputs = result["outputs"] as? [String],let first = outputs.first,
              let pdf = PDFDocument(url:URL(fileURLWithPath:first)),pdf.pageCount == 3,
              pdf.string?.contains("158000") == true else {throw EngineError(message:"Native bridge output validation failed")}
        let data = try JSONSerialization.data(withJSONObject:["ok":true,"pages":pdf.pageCount,"outputs":outputs],options:.sortedKeys)
        print(String(decoding:data,as:UTF8.self))
    }
}
