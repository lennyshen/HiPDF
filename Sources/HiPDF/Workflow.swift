import SwiftUI
import UniformTypeIdentifiers

struct WorkflowView: View {
    @EnvironmentObject var store: AppStore
    @State private var name = "我的文档流程"
    @State private var steps: [WorkflowStep] = []
    @State private var selected: UUID?
    @State private var files: [URL] = []
    @State private var message = ""
    @State private var error = ""
    @State private var running = false
    @State private var outputs: [String] = []
    @State private var progress: Double = 0
    let engine = EngineClient()
    let allowed: Set<String> = ["merge","split","compress","delete","extract","organize","rotate","numbers","watermark","crop","unlock","repair","ocr","pdfa"]
    var body: some View {
        VStack(alignment:.leading,spacing:22) {
            HStack {VStack(alignment:.leading,spacing:7) {Text("工作流程").font(.system(size:28,weight:.semibold));Text("把重复步骤，变成一次操作。").font(.system(size:12)).foregroundStyle(Color.muted)};Spacer();Menu("载入流程") {ForEach(store.workflows) {workflow in Button(workflow.name) {steps = workflow.steps;name = workflow.name;selected = steps.first?.id}};Divider();Button("导入流程文件…",action:importTemplate)};Button("保存流程",action:saveTemplate).disabled(steps.isEmpty)}
            HStack(spacing:12) {Image(systemName:"point.3.connected.trianglepath.dotted").foregroundStyle(Color.accent);TextField("流程名称",text:$name).textFieldStyle(.plain).font(.system(size:16,weight:.medium));Spacer();Button("导出…",action:exportTemplate).disabled(steps.isEmpty)}.padding(17).background(Color.white,in:RoundedRectangle(cornerRadius:12))
            HStack(alignment:.top,spacing:20) {
                VStack(alignment:.leading,spacing:14) {
                    SmallLabel(title:"流程步骤")
                    if steps.isEmpty {Text("添加工具，按顺序自动执行。\n例如：OCR → 压缩 → 添加页码。").font(.system(size:12)).foregroundStyle(Color.muted).lineSpacing(6).padding(.vertical,22)}
                    ScrollView {
                        VStack(spacing:10) {ForEach(Array(steps.enumerated()),id:\.element.id) {index,step in
                            if let tool = store.tools.first(where:{$0.id == step.tool}) {
                                HStack(spacing:10) {
                                    Text(String(format:"%02d",index+1)).font(.system(size:10,design:.monospaced)).foregroundStyle(Color.muted)
                                    Button {selected = step.id} label:{HStack{ToolIcon(tool:tool,size:32);Text(tool.name).font(.system(size:12,weight:.medium));Spacer()}}.buttonStyle(.plain)
                                    Button {if index>0 {steps.swapAt(index,index-1)}} label:{Image(systemName:"arrow.up")}.disabled(index==0)
                                    Button {if index+1<steps.count {steps.swapAt(index,index+1)}} label:{Image(systemName:"arrow.down")}.disabled(index+1==steps.count)
                                    Button {steps.removeAll {$0.id == step.id}} label:{Image(systemName:"xmark")}
                                }.buttonStyle(.plain).font(.system(size:10)).padding(12).background(selected == step.id ? Color.accent.opacity(0.06) : Color.white,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(Color.black.opacity(0.04)))
                            }
                        }}
                    }
                    Menu {ForEach(store.tools.filter {allowed.contains($0.id)}) {tool in Button(tool.name) {let step = WorkflowStep(tool:tool.id,options:tool.defaults);steps.append(step);selected = step.id}}} label:{Label("添加步骤",systemImage:"plus.circle")}.menuStyle(.borderlessButton).fixedSize()
                    Spacer()
                    Divider()
                    HStack {Button {chooseFiles()} label:{Label("选择 PDF 文件",systemImage:"plus")};Text("\(files.count) 个文件").font(.system(size:11)).foregroundStyle(Color.muted)}
                    ForEach(files,id:\.path) {url in Text(url.lastPathComponent).font(.system(size:11)).lineLimit(1)}
                    Text("每一步的输出都会交给下一步。\n模板不保存密码；中间文件保留在本次任务目录。").font(.system(size:10)).foregroundStyle(Color.muted).lineSpacing(5)
                }.frame(maxWidth:.infinity,alignment:.leading)
                ScrollView {
                    if let index = steps.firstIndex(where:{$0.id == selected}),let tool = store.tools.first(where:{$0.id == steps[index].tool}) {
                        VStack(alignment:.leading,spacing:17) {Text(tool.name+" · 选项").font(.system(size:14,weight:.semibold));OptionsEditor(tool:tool,values:Binding(get:{steps.indices.contains(index) ? steps[index].options : [:]},set:{if steps.indices.contains(index){steps[index].options = $0}}))}.padding(20)
                    } else {Text("选择步骤以设置参数").font(.system(size:12)).foregroundStyle(Color.muted).padding(24)}
                }.frame(width:275).frame(maxHeight:.infinity).background(Color.white,in:RoundedRectangle(cornerRadius:13))
            }.disabled(running)
            if !error.isEmpty {Text(error).font(.system(size:12)).foregroundStyle(Color.orange)}
            if !message.isEmpty {Text(message).font(.system(size:11)).foregroundStyle(Color.accent)}
            HStack {if !outputs.isEmpty {Button("在 Finder 中显示结果") {NSWorkspace.shared.activateFileViewerSelecting(outputs.map {URL(fileURLWithPath:$0)})}};Spacer();if running {ProgressView(value:progress).frame(width:130);Button("取消") {engine.cancel()}} else {Button("运行工作流程",action:run).buttonStyle(PrimaryButtonStyle()).disabled(steps.isEmpty || files.isEmpty)}}
        }.padding(32).padding(.top,24)
    }
    func chooseFiles() {let panel = NSOpenPanel();panel.allowedContentTypes = [.pdf];panel.allowsMultipleSelection = true;if panel.runModal() == .OK {files = panel.urls}}
    var template:WorkflowTemplate { .init(name:name,steps:steps.map {s in var safe = s;safe.options = s.options.filter {!["password","newPassword","certPassword"].contains($0.key)};return safe}) }
    func saveTemplate() {if let index = store.workflows.firstIndex(where:{$0.name == name}) {store.workflows[index] = template} else {store.workflows.append(template)};message = "流程已保存在这台 Mac。"}
    func exportTemplate() {let panel = NSSavePanel();panel.allowedContentTypes = [.json];panel.nameFieldStringValue = name+".json";if panel.runModal() == .OK,let url = panel.url {do {let encoder = JSONEncoder();encoder.outputFormatting = [.prettyPrinted,.sortedKeys];try encoder.encode(template).write(to:url,options:.atomic);message = "流程已导出。"} catch {self.error = error.localizedDescription}}}
    func importTemplate() {let panel = NSOpenPanel();panel.allowedContentTypes = [.json];if panel.runModal() == .OK,let url = panel.url {do {let value = try JSONDecoder().decode(WorkflowTemplate.self,from:Data(contentsOf:url));guard value.steps.allSatisfy({allowed.contains($0.tool)}),value.steps.count<=100 else {throw EngineError(message:"流程包含不支持的工具或步骤过多。")};name = value.name;steps = value.steps;selected = steps.first?.id} catch {self.error = error.localizedDescription}}}
    func run() {
        running = true;store.busy = true;error = "";outputs = [];message = "准备工作流程…"
        Task {defer {running = false;store.busy = false};do {
            // Current-session passwords may be used, but never serialized to templates.
            let runtimeSteps: [[String:Any]] = steps.map {["tool":$0.tool,"options":$0.options]}
            let result = try await engine.run(["action":"workflow","files":files.map(\.path),"options":["steps":runtimeSteps],"outputDir":UserDefaults.standard.string(forKey:"outputDirectory") ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/HiPDF").path]) {text,value in Task {@MainActor in message = text;progress = value}}
            outputs = result["outputs"] as? [String] ?? [];message = "工作流程完成，共生成 \(outputs.count) 个结果。";store.record(tool:"workflow",outputs:outputs,count:files.count)
        } catch {self.error = error.localizedDescription}}
    }
}
