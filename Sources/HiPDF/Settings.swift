import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var config = AIConfiguration.load()
    @State private var apiKey = ""
    @State private var reveal = false
    @State private var status = ""
    @State private var testing = false
    @State private var engineState: [String:Any] = [:]
    @State private var tab = "ai"
    let client = EngineClient()
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:13) { Image(systemName:"slider.horizontal.3").font(.system(size:21)).foregroundStyle(Color.accent); VStack(alignment:.leading,spacing:4) {Text("HiPDF 设置").font(.system(size:23,weight:.semibold));Text("你的文档，你的处理方式。").font(.system(size:11)).foregroundStyle(Color.muted)};Spacer();Button {dismiss()} label:{Image(systemName:"xmark.circle.fill").foregroundStyle(Color.muted)}.buttonStyle(.plain) }.padding(26)
            Picker("设置分类",selection:$tab) {Text("AI 服务").tag("ai");Text("本地引擎").tag("engine");Text("关于").tag("about")}.pickerStyle(.segmented).padding(.horizontal,26).padding(.bottom,20)
            ScrollView {
                VStack(alignment:.leading,spacing:19) {
                    if tab == "ai" { aiSettings }
                    else if tab == "engine" { engineSettings }
                    else { about }
                }.padding(.horizontal,29).padding(.bottom,24)
            }
            if !status.isEmpty { Text(status).font(.system(size:11)).foregroundStyle(Color.accent).textSelection(.enabled).padding(.horizontal,26).padding(.vertical,12).frame(maxWidth:.infinity,alignment:.leading).background(Color.accent.opacity(0.05)) }
            Divider()
            HStack { if tab == "ai" {Button {testConnection()} label:{HStack{if testing {ProgressView().controlSize(.small)};Text(testing ? "正在测试…" : "测试连接")}}.disabled(testing)};Spacer();Button("取消") {dismiss()};Button("保存设置",action:save).buttonStyle(PrimaryButtonStyle()).disabled(testing) }.padding(22)
        }.frame(width:620,height:710).background(Color.canvas).foregroundStyle(Color.ink).preferredColorScheme(.light)
        .task {apiKey = KeychainStore.read();do {engineState = try await EngineClient().run(["action":"health"])} catch {engineState = ["error":error.localizedDescription]}}
        .onDisappear {client.cancel()}
    }
    var aiSettings: some View {
        VStack(alignment:.leading,spacing:19) {
            VStack(alignment:.leading,spacing:7) {Label("连接你信任的 AI",systemImage:"sparkles").font(.system(size:15,weight:.semibold));Text("支持 OpenAI、兼容服务与本机模型。普通 PDF 工具离线处理；只有你启动摘要或翻译时，文档文字才会发送到此地址。").font(.system(size:11)).foregroundStyle(Color.muted).lineSpacing(4)}
            settingField("API 地址",hint:"填写服务的 Base URL（通常以 /v1 结尾），也支持完整的 /chat/completions 地址。") {TextField("https://api.example.com/v1",text:$config.baseURL)}
            settingField("API Key",hint:"仅保存到这台 Mac 的钥匙串。本机无需认证的服务可留空。") {
                HStack {if reveal {TextField("sk-…",text:$apiKey)} else {SecureField("sk-…",text:$apiKey)};Button {reveal.toggle()} label:{Image(systemName:reveal ? "eye.slash" : "eye")}.buttonStyle(.plain)}
            }
            settingField("模型名称",hint:"使用服务商提供的准确模型 ID，例如 gpt-4.1-mini 或你的本地模型名。") {TextField("填写模型名称",text:$config.model)}
            DisclosureGroup("高级兼容选项") {
                VStack(alignment:.leading,spacing:15) {
                    HStack(spacing:18) {settingField("超时（秒）") {TextField("120",text:$config.timeout)};settingField("输出 Token 上限") {TextField("4096",text:$config.maxTokens)}}
                    settingField("每段最大字数",hint:"长文会完整分段处理。若服务提示上下文超限，请降低此值。") {TextField("7000",text:$config.chunkSize)}
                    Picker("输出长度参数",selection:$config.tokenParameter) {Text("max_tokens").tag("max_tokens");Text("max_completion_tokens").tag("max_completion_tokens")}.font(.system(size:11))
                    Toggle("发送 temperature 参数",isOn:$config.sendTemperature).font(.system(size:11))
                    Text("部分推理模型要求 max_completion_tokens，且不接受 temperature。按服务商接口要求设置。").font(.system(size:10)).foregroundStyle(Color.muted)
                }.padding(.top,15)
            }.font(.system(size:12))
        }.textFieldStyle(.roundedBorder)
    }
    var engineSettings: some View {
        VStack(alignment:.leading,spacing:20) {
            Text("所有引擎在本机运行").font(.system(size:19,weight:.semibold))
            engineRow("PDF 处理",detail:engineState["engine"] as? String ?? "正在检测…",available:engineState["engine"] != nil)
            engineRow("Office 转换",detail:"Word、PowerPoint、Excel 导入与 PDF/A 导出",available:engineState["office"] as? Bool == true)
            engineRow("离线文字识别",detail:"macOS Vision · 中文、英文及系统支持的语言",available:engineState["ocr"] as? Bool == true)
            if let error = engineState["error"] as? String {Text(error).font(.system(size:11)).foregroundStyle(.red)}
            Divider()
            Text("文件保存").font(.system(size:13,weight:.semibold))
            Text("每次处理创建独立的结果文件夹。原文件不会被覆盖。可在工具页面左下角修改保存位置，任务历史只记录输出路径与处理时间。").font(.system(size:12)).foregroundStyle(Color.muted).lineSpacing(5)
            Text("扫描与转换质量").font(.system(size:13,weight:.semibold))
            Text("OCR、复杂 Office 版式、自动表单检测和翻译版面可能需要人工校对。密文删除会清理真实内容；裁剪仅改变页面可见范围。证书签名不自动提供可信时间戳。").font(.system(size:12)).foregroundStyle(Color.muted).lineSpacing(5)
        }
    }
    var about: some View {
        VStack(alignment:.leading,spacing:20) {
            Text("HiPDF").font(.system(size:38,weight:.bold,design:.rounded))
            Text("1.0.0 · macOS 14+ · Apple Silicon").font(.system(size:12)).foregroundStyle(Color.muted)
            Text("一个本地优先的 PDF 工作空间，提供 33 个工具和可重复使用的处理流程。功能参考 iLovePDF，界面与代码为独立实现，与 iLovePDF 无隶属关系。").font(.system(size:13)).lineSpacing(6)
            Button("阅读使用说明") {NSWorkspace.shared.open(ResourceLocation.root.appendingPathComponent("USER_GUIDE.html"))}
            Button("查看功能覆盖与限制") {NSWorkspace.shared.open(ResourceLocation.root.appendingPathComponent("FEATURES.md"))}
            Button("查看开源组件许可证") {NSWorkspace.shared.open(ResourceLocation.root.appendingPathComponent("THIRD_PARTY_NOTICES.md"))}
        }
    }
    func settingField<Content:View>(_ title:String,hint:String = "",@ViewBuilder content:()->Content)->some View {
        VStack(alignment:.leading,spacing:7) {Text(title).font(.system(size:11,weight:.medium));content();if !hint.isEmpty {Text(hint).font(.system(size:10)).foregroundStyle(Color.muted).fixedSize(horizontal:false,vertical:true)}}
    }
    func engineRow(_ title:String,detail:String,available:Bool)->some View {
        HStack(spacing:13) {Image(systemName:available ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(available ? Color.accent : Color.orange);VStack(alignment:.leading,spacing:5) {Text(title).font(.system(size:13,weight:.medium));Text(detail).font(.system(size:10)).foregroundStyle(Color.muted)};Spacer();Text(available ? "已就绪" : "未就绪").font(.system(size:10)).foregroundStyle(Color.muted)}.padding(15).background(Color.white,in:RoundedRectangle(cornerRadius:11))
    }
    func validate()->Bool {
        guard !config.model.trimmingCharacters(in:.whitespaces).isEmpty else {status = "请填写模型名称。";return false}
        guard let url = URL(string:config.baseURL),["https","http"].contains(url.scheme ?? ""),url.host != nil else {status = "请填写有效的 API 地址。";return false}
        return true
    }
    func save() {do {try KeychainStore.save(apiKey);config.save();dismiss()} catch {status = error.localizedDescription}}
    func testConnection() {
        guard validate() else {return};testing = true;status = "测试请求只发送连通性检查文本，不发送文档。"
        Task {defer {testing = false};do {let result = try await client.run(["action":"aiTest","ai":config.dictionary(apiKey:apiKey)]);status = "连接成功 · "+(result["message"] as? String ?? "兼容接口响应正常")} catch {status = error.localizedDescription}}
    }
}
