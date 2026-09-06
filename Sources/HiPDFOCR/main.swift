import Foundation
import Vision
import AppKit

func output(_ value: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: value), let str = String(data: data, encoding: .utf8) { print(str) }
}
guard CommandLine.arguments.count >= 2 else { output(["error": "缺少图像路径。"]); exit(1) }
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true
request.automaticallyDetectsLanguage = true
let desired = CommandLine.arguments.count > 2 ? CommandLine.arguments[2].split(separator: ",").map(String.init) : ["zh-Hans", "en-US"]
do {
    let supported = try request.supportedRecognitionLanguages()
    let languages = desired.filter { supported.contains($0) }
    guard !languages.isEmpty else { output(["error": "当前系统不支持所选 OCR 语言。"]); exit(1) }
    request.recognitionLanguages = languages
    try VNImageRequestHandler(url: url, options: [:]).perform([request])
    let lines: [[String: Any]] = (request.results ?? []).compactMap { item in
        guard let candidate = item.topCandidates(1).first else { return nil }
        let r = item.boundingBox
        return ["text": candidate.string, "confidence": candidate.confidence, "box": [r.minX,r.minY,r.width,r.height]]
    }
    output(["lines": lines])
} catch { output(["error": "macOS 无法识别此图像。"]); exit(1) }
