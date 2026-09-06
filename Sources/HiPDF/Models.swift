import SwiftUI
import AppKit
import PDFKit

extension Color {
    init(hex: String) {
        let value = UInt64(hex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0x176E62
        self.init(.sRGB, red: Double((value >> 16) & 255)/255, green: Double((value >> 8) & 255)/255, blue: Double(value & 255)/255, opacity: 1)
    }
    static let ink = Color(hex: "243B35")
    static let accent = Color(hex: "23796B")
    static let canvas = Color(hex: "F7F8F5")
    static let muted = Color(hex: "7C8983")
}

struct ToolChoice: Codable, Hashable { var value: String; var label: String }
struct ToolOption: Codable, Identifiable {
    var key: String; var label: String; var `default`: String; var kind: String; var choices: [ToolChoice]; var help: String
    var id: String { key }
}
struct PDFTool: Codable, Identifiable, Hashable {
    var id: String; var name: String; var subtitle: String; var icon: String; var category: String; var color: String
    var options: [ToolOption]; var extensions: [String]; var hint: String; var many: Bool
    var tint: Color { Color(hex: color) }
    var isAI: Bool { ["summarize", "translate"].contains(id) }
    var canDraw: Bool { ["edit", "sign", "crop", "redact", "forms"].contains(id) }
    var defaults: [String: String] { Dictionary(uniqueKeysWithValues: options.map { ($0.key, $0.default) }) }
    static func == (a: PDFTool,b: PDFTool) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
struct Category: Identifiable {
    var id: String; var name: String; var icon: String
    static let all: [Category] = [
        .init(id: "arrange", name: "整理页面", icon: "square.stack.3d.up"),
        .init(id: "convert", name: "格式转换", icon: "arrow.triangle.2.circlepath"),
        .init(id: "optimize", name: "优化与修复", icon: "slider.horizontal.3"),
        .init(id: "edit", name: "编辑与标注", icon: "pencil.and.outline"),
        .init(id: "security", name: "安全与签名", icon: "lock.shield"),
        .init(id: "ai", name: "智能文档", icon: "sparkles")]
}
struct JobRecord: Codable, Identifiable {
    var id = UUID(); var tool: String; var date = Date(); var outputs: [String]; var count: Int
}
struct WorkflowStep: Codable, Identifiable {
    var id = UUID(); var tool: String; var options: [String: String]
    var json: [String: Any] { ["tool": tool, "options": options.filter { !["password", "newPassword", "certPassword"].contains($0.key) }] }
}
struct WorkflowTemplate: Codable, Identifiable { var id = UUID(); var name: String; var steps: [WorkflowStep] }
struct PageRegion: Identifiable {
    var id = UUID(); var page: Int; var rect: [Double]; var mode: String; var text: String; var points: [[Double]] = []
    var json: [String: Any] { ["page": page, "rect": rect, "mode": mode, "text": text, "points": points] }
}
struct InputFile: Identifiable {
    var url: URL; var id: String { url.path }; var pages: Int = 0; var bytes: Int64 = 0
    init(url: URL) {
        self.url = url
        bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        // Page metadata arrives with the asynchronous preview. Reading a cloud
        // placeholder here blocks file import on the main thread.
    }
}
enum ResourceLocation {
    static var root: URL {
        if let url = Bundle.main.resourceURL, FileManager.default.fileExists(atPath: url.appendingPathComponent("tools.json").path) { return url }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
    }
    static var project: URL { root.deletingLastPathComponent() }
}

@MainActor final class AppStore: ObservableObject {
    @Published var route = "home"
    @Published var currentTool: PDFTool?
    @Published var query = ""
    @Published var showSettings = false
    @Published var busy = false
    @Published var favorites: Set<String> { didSet { UserDefaults.standard.set(Array(favorites), forKey: "favorites") } }
    @Published var history: [JobRecord] { didSet { persist(history,key: "history") } }
    @Published var workflows: [WorkflowTemplate] { didSet { persist(workflows,key: "workflows") } }
    @Published var incomingFiles: [URL] = []
    @Published var catalogError: String?
    let tools: [PDFTool]
    init() {
        let defaults = UserDefaults.standard
        favorites = Set(defaults.stringArray(forKey: "favorites") ?? ["merge", "compress", "pdfToWord", "summarize"])
        history = defaults.data(forKey: "history").flatMap { try? JSONDecoder().decode([JobRecord].self, from: $0) } ?? []
        workflows = defaults.data(forKey: "workflows").flatMap { try? JSONDecoder().decode([WorkflowTemplate].self, from: $0) } ?? []
        do { tools = try JSONDecoder().decode([PDFTool].self, from: Data(contentsOf: ResourceLocation.root.appendingPathComponent("tools.json"))) }
        catch { tools = []; catalogError = "工具配置无法加载，请重新构建应用。" }
    }
    func persist<T: Encodable>(_ value: T,key: String) { if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data,forKey:key) } }
    func toggleFavorite(_ id: String) { if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) } }
    func open(_ tool: PDFTool,files: [URL] = []) { guard !busy else { return }; incomingFiles = files; currentTool = tool; query = "" }
    func record(tool: String,outputs: [String],count: Int) { history.insert(.init(tool:tool,outputs:outputs,count:count),at:0); history = Array(history.prefix(100)) }
}

struct ToolIcon: View {
    var tool: PDFTool; var size: CGFloat = 44
    var body: some View {
        Image(systemName: tool.icon).font(.system(size: size*0.46, weight: .medium)).foregroundStyle(tool.tint)
            .frame(width:size,height:size).background(tool.tint.opacity(0.10),in:RoundedRectangle(cornerRadius:size*0.28))
    }
}
struct SmallLabel: View {
    var title: String
    var body: some View { Text(title).font(.system(size:11,weight:.semibold)).tracking(1.4).foregroundStyle(Color.muted) }
}
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size:13,weight:.semibold)).foregroundStyle(.white).padding(.horizontal,18).padding(.vertical,12)
            .background(Color.accent.opacity(configuration.isPressed ? 0.8 : 1),in:RoundedRectangle(cornerRadius:10))
    }
}
