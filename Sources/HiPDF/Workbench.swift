import SwiftUI
import PDFKit
import UniformTypeIdentifiers

@MainActor final class WorkbenchModel: ObservableObject {
    let tool: PDFTool
    @Published var files: [InputFile] = []
    @Published var selected = ""
    @Published var options: [String:String]
    @Published var regions: [PageRegion] = []
    @Published var running = false
    @Published var progress: Double = 0
    @Published var message = ""
    @Published var error: String?
    @Published var outputs: [String] = []
    @Published var notes: [String] = []
    @Published var fields: [[String:Any]] = []
    @Published var formValues: [String:String] = [:]
    @Published var outputDirectory = UserDefaults.standard.string(forKey:"outputDirectory") ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/HiPDF").path
    @Published var showResult = false
    let engine = EngineClient()
    let htmlExporter = HTMLExporter()
    init(tool: PDFTool) { self.tool = tool; options = tool.defaults }
    var currentURL: URL? {
        if showResult, let output = outputs.first(where:{$0.lowercased().hasSuffix(".pdf")}) { return URL(fileURLWithPath:output) }
        return files.first(where:{$0.id == selected})?.url ?? files.first?.url
    }
    func add(_ urls: [URL]) {
        let valid = urls.filter { tool.extensions.contains($0.pathExtension.lowercased()) && $0.isFileURL }
        if valid.count != urls.count { error = "部分文件格式不受此工具支持。支持："+tool.extensions.joined(separator:", ") }
        if !tool.many { files = valid.prefix(1).map(InputFile.init); regions = [] }
        else { for url in valid where !files.contains(where:{$0.url == url}) { files.append(.init(url:url)) } }
        selected = files.first?.id ?? ""; showResult = false; outputs = []; fields = []; formValues = [:]
    }
    func chooseFiles() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = tool.extensions.compactMap { UTType(filenameExtension:$0) }; panel.allowsMultipleSelection = tool.many
        if panel.runModal() == .OK { add(panel.urls) }
    }
    func move(_ id:String,by offset:Int) {
        guard let index = files.firstIndex(where:{$0.id == id}),files.indices.contains(index+offset) else { return }; files.swapAt(index,index+offset)
    }
    func chooseOutput() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        if panel.runModal() == .OK,let url = panel.url { outputDirectory = url.path; UserDefaults.standard.set(url.path,forKey:"outputDirectory") }
    }
    func inspectForms() async {
        guard tool.id == "forms",let file = files.first else { return }
        do {
            let result = try await EngineClient().run(["action":"inspect","files":[file.id],"options":options])
            fields = (result["files"] as? [[String:Any]])?.first?["fields"] as? [[String:Any]] ?? []
            formValues = Dictionary(fields.compactMap { field in guard let name = field["name"] as? String else {return nil}; return (name,field["value"] as? String ?? "") },uniquingKeysWith: { first,_ in first })
        } catch { self.error = error.localizedDescription }
    }
    func run(store: AppStore) {
        guard !running else {return}
        running = true; store.busy = true; error = nil; outputs = []; notes = []; progress = 0.01; message = "正在准备文件…"; showResult = false
        Task {
            defer { running = false; store.busy = false }
            do {
                let result: [String:Any]
                if tool.id == "htmlToPDF" {
                    message = "正在加载网页并分页…"
                    let urls = try await htmlExporter.export(source:files.first?.url,options:options,outputDirectory:outputDirectory)
                    result = ["outputs":urls.map(\.path),"notes":["已使用 macOS WebKit 按纸张分页导出。需要登录的网页可能无法完整加载。"]]
                } else {
                    var params: [String:Any] = options
                    params["regions"] = regions.map(\.json)
                    params["formValues"] = formValues
                    var request: [String:Any] = ["action":tool.id,"files":files.map(\.id),"outputDir":outputDirectory,"options":params]
                    if tool.isAI { request["ai"] = AIConfiguration.load().dictionary() }
                    result = try await engine.run(request) { text,value in Task { @MainActor in self.message = text; self.progress = value } }
                }
                outputs = result["outputs"] as? [String] ?? []
                notes = result["notes"] as? [String] ?? []
                progress = 1; message = "处理完成"; showResult = true
                store.record(tool:tool.id,outputs:outputs,count:files.count)
            } catch { self.error = error.localizedDescription; message = "未完成处理" }
        }
    }
    func cancel() { message = "正在取消并清理临时文件…"; engine.cancel(); htmlExporter.cancel() }
}

struct WorkbenchView: View {
    @EnvironmentObject var store: AppStore
    let tool: PDFTool
    @StateObject private var model: WorkbenchModel
    @State private var dropping = false
    @State private var scanner = false
    @State private var documentText: String?
    init(tool: PDFTool) { self.tool = tool; _model = StateObject(wrappedValue:WorkbenchModel(tool:tool)) }
    var body: some View {
        VStack(spacing:0) {
            header
            if !model.files.isEmpty { fileQueue }
            HStack(spacing:0) {
                preview.frame(maxWidth:.infinity,maxHeight:.infinity)
                Rectangle().fill(Color.black.opacity(0.06)).frame(width:1)
                inspector.frame(width:288).background(Color.white)
            }
            if model.error != nil || !model.outputs.isEmpty { feedback }
            footer
        }
        .onAppear { if !store.incomingFiles.isEmpty { model.add(store.incomingFiles); store.incomingFiles = [] } }
        .onReceive(NotificationCenter.default.publisher(for:.hipdfOpen)) { _ in if !model.running && store.currentTool?.id == tool.id { model.chooseFiles() } }
        .onDrop(of:[UTType.fileURL.identifier],isTargeted:$dropping) { providers in guard !model.running else{return false}; collectDroppedURLs(providers) { model.add($0) }; return true }
        .overlay { if dropping { RoundedRectangle(cornerRadius:12).stroke(Color.accent,style:StrokeStyle(lineWidth:3,dash:[7])).padding(8).allowsHitTesting(false) } }
        .task(id:model.files.first?.id ?? "") { await model.inspectForms() }
        .sheet(isPresented:$scanner) { ScannerSheet { urls in model.add(urls); scanner = false } }
        .sheet(isPresented:Binding(get:{documentText != nil},set:{if !$0 {documentText = nil}})) {
            VStack(alignment:.leading,spacing:16) {
                HStack { Text("文本结果").font(.title2); Spacer(); Button("复制全文") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(documentText ?? "",forType:.string) }; Button("关闭") {documentText = nil} }
                TextEditor(text:Binding(get:{documentText ?? ""},set:{_ in})).font(.system(size:13,design:.monospaced))
            }.padding(24).frame(width:800,height:600)
        }
    }
    var header: some View {
        HStack(spacing:13) {
            Button { store.currentTool = nil } label: { Image(systemName:"chevron.left").frame(width:26,height:32) }.buttonStyle(.plain).disabled(model.running).help("返回工作台")
            ToolIcon(tool:tool,size:35)
            VStack(alignment:.leading,spacing:4) { Text(tool.name).font(.system(size:20,weight:.semibold)); Text(tool.subtitle).font(.system(size:11)).foregroundStyle(Color.muted) }
            Spacer()
            if tool.isAI { Button { store.showSettings = true } label: { Label("AI 设置",systemImage:"sparkles") }.font(.system(size:11)).disabled(model.running) }
            if tool.id == "scan" { Button { scanner = true } label: { Label("连接扫描仪",systemImage:"scanner") }.disabled(model.running) }
            Button { model.chooseFiles() } label: { Label("添加文件",systemImage:"plus") }.disabled(model.running)
        }.padding(.horizontal,22).padding(.top,33).padding(.bottom,20)
    }
    var fileQueue: some View {
        ScrollView(.horizontal,showsIndicators:false) {
            HStack(spacing:9) {
                ForEach(model.files) { file in
                    HStack(spacing:8) {
                        Button { model.selected = file.id; model.regions = []; model.showResult = false } label: {
                            HStack(spacing:7) { Image(systemName:"doc").foregroundStyle(tool.tint); VStack(alignment:.leading,spacing:3) { Text(file.url.lastPathComponent).lineLimit(1).font(.system(size:11,weight:.medium)); Text("\(file.pages > 0 ? "\(file.pages) 页 · " : "")\(ByteCountFormatter.string(fromByteCount:file.bytes,countStyle:.file))").font(.system(size:9)).foregroundStyle(Color.muted) } }
                        }.buttonStyle(.plain)
                        if model.files.count>1 {
                            VStack(spacing:3) { Button {model.move(file.id,by:-1)} label:{Image(systemName:"chevron.left")}; Button {model.move(file.id,by:1)} label:{Image(systemName:"chevron.right")} }.font(.system(size:8)).buttonStyle(.plain)
                        }
                        Button { model.files.removeAll {$0.id == file.id}; model.regions = []; model.showResult = false } label: { Image(systemName:"xmark").font(.system(size:9)) }.buttonStyle(.plain).foregroundStyle(Color.muted)
                    }.padding(10).frame(maxWidth:240).background(model.selected == file.id ? Color.accent.opacity(0.07) : Color.white,in:RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(Color.black.opacity(0.055)))
                }
            }.padding(.horizontal,25).padding(.vertical,9)
        }.background(Color.white.opacity(0.45)).disabled(model.running)
    }
    @ViewBuilder var preview: some View {
        if let url = model.currentURL, url.pathExtension.lowercased() == "pdf" {
            PDFPreviewPane(url:url,password:model.showResult ? (tool.id == "encrypt" ? model.options["newPassword",default:""] : "") : model.options["password",default:""],
                           selectable:!model.running && !model.showResult,
                           tool:tool,options:$model.options,regions:$model.regions,isResult:model.showResult) { pageCount in
                if !model.showResult, let index = model.files.firstIndex(where: { $0.url == url }) { model.files[index].pages = pageCount }
            }
        } else if let url = model.currentURL,let image = NSImage(contentsOf:url) {
            VStack(spacing:14) { Image(nsImage:image).resizable().scaledToFit().padding(32); Text(url.lastPathComponent).font(.system(size:11)).foregroundStyle(Color.muted) }.padding(.bottom,20)
        } else {
            VStack(spacing:18) {
                ZStack { RoundedRectangle(cornerRadius:21).fill(tool.tint.opacity(0.1)).frame(width:90,height:100); Image(systemName:tool.icon).font(.system(size:35,weight:.light)).foregroundStyle(tool.tint) }
                Text(model.files.isEmpty ? "把文件放在这里" : "文件已准备就绪").font(.system(size:22,weight:.medium))
                Text(model.files.isEmpty ? "拖入文件，或从 Mac 中选择\n支持 \(tool.extensions.map {$0.uppercased()}.joined(separator:"、"))" : "\(model.files.count) 个文件，等待转换。\n完成后可以在这里预览 PDF。").font(.system(size:12)).foregroundStyle(Color.muted).multilineTextAlignment(.center).lineSpacing(6)
                Button { model.chooseFiles() } label: { Label("选择文件",systemImage:"plus") }.buttonStyle(PrimaryButtonStyle()).disabled(model.running)
                if tool.id == "htmlToPDF" { Text("也可直接在右侧输入网页地址。").font(.system(size:11)).foregroundStyle(Color.muted) }
            }.frame(maxWidth:.infinity,maxHeight:.infinity).padding(32)
        }
    }
    var inspector: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                HStack { SmallLabel(title:"处理选项"); Spacer(); if model.showResult { Button("返回原文件") {model.showResult = false}.font(.system(size:10)) } }
                if !tool.hint.isEmpty { Text(tool.hint).font(.system(size:11)).foregroundStyle(Color.muted).lineSpacing(5).fixedSize(horizontal:false,vertical:true) }
                OptionsEditor(tool:tool,values:$model.options)
                if tool.id == "forms" && model.options["formMode"] == "fill" { formEditor }
                if tool.canDraw && !model.regions.isEmpty {
                    Divider()
                    HStack { Text("已选择 \(model.regions.count) 个区域").font(.system(size:11,weight:.medium)); Spacer(); Button("撤销") {_ = model.regions.popLast()}.font(.system(size:10)); Button("清空") {model.regions = []}.font(.system(size:10)) }
                }
                if tool.isAI {
                    let config = AIConfiguration.load()
                    VStack(alignment:.leading,spacing:6) {
                        Label("当前 AI 服务",systemImage:"network").font(.system(size:11,weight:.medium))
                        Text(config.model.isEmpty ? "尚未配置模型" : config.model).font(.system(size:11)).foregroundStyle(Color.muted)
                        Text(URL(string:config.baseURL)?.host ?? config.baseURL).font(.system(size:10)).foregroundStyle(Color.muted).textSelection(.enabled)
                    }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.accent.opacity(0.045),in:RoundedRectangle(cornerRadius:9))
                }
            }.padding(21)
        }.disabled(model.running)
    }
    var formEditor: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Text("已有字段").font(.system(size:12,weight:.semibold)); Spacer(); Button("读取字段") {Task {await model.inspectForms()}}.font(.system(size:10)) }
            if model.fields.isEmpty { Text("暂无可填写字段。加密文件可填写密码后重新读取；也可切换到创建字段。").font(.system(size:11)).foregroundStyle(Color.muted) }
            ForEach(Array(model.fields.enumerated()),id:\.offset) { _,field in
                if let name = field["name"] as? String {
                    let type = field["type"] as? String ?? ""
                    VStack(alignment:.leading,spacing:5) {
                        Text(name).font(.system(size:11))
                        if ["CheckBox","RadioButton"].contains(type) {
                            Toggle("选中",isOn:Binding(get:{!["Off","","false"].contains(model.formValues[name,default:""])},set:{model.formValues[name] = $0 ? "true" : "false"})).font(.system(size:11))
                        } else if let choices = field["choices"] as? [String],!choices.isEmpty {
                            Picker(name,selection:Binding(get:{model.formValues[name,default:""]},set:{model.formValues[name] = $0})) { Text("未选择").tag(""); ForEach(choices,id:\.self) {Text($0).tag($0)} }.labelsHidden()
                        } else { TextField("填写内容",text:Binding(get:{model.formValues[name,default:""]},set:{model.formValues[name] = $0})).textFieldStyle(.roundedBorder) }
                    }
                }
            }
        }
    }
    var feedback: some View {
        VStack(alignment:.leading,spacing:8) {
            if let error = model.error {
                HStack(alignment:.top,spacing:8) { Image(systemName:"exclamationmark.circle").foregroundStyle(Color(hex:"B36B4C")); Text(error).font(.system(size:12)).textSelection(.enabled); Spacer(); Button {model.error = nil} label:{Image(systemName:"xmark")}.buttonStyle(.plain) }
            }
            if !model.outputs.isEmpty {
                HStack(spacing:10) {
                    Image(systemName:"checkmark.circle.fill").foregroundStyle(Color.accent)
                    Text("已生成 \(model.outputs.count) 个文件").font(.system(size:12,weight:.medium))
                    Spacer()
                    Menu("打开结果") { ForEach(model.outputs,id:\.self) { path in Button(URL(fileURLWithPath:path).lastPathComponent) { if path.hasSuffix(".md"),let text = try? String(contentsOfFile:path,encoding:.utf8) {documentText = text} else {NSWorkspace.shared.open(URL(fileURLWithPath:path))} } } }
                    Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting(model.outputs.map {URL(fileURLWithPath:$0)}) }
                }
                ForEach(model.notes,id:\.self) { Text($0).font(.system(size:10.5)).foregroundStyle(Color.muted).fixedSize(horizontal:false,vertical:true) }
            }
        }.padding(.horizontal,25).padding(.vertical,14).background(Color(hex:"EDF3E9"))
    }
    var footer: some View {
        HStack(spacing:15) {
            VStack(alignment:.leading,spacing:5) {
                HStack(spacing:5) { Image(systemName:"folder"); Text("保存至"); Button(URL(fileURLWithPath:model.outputDirectory).lastPathComponent) {model.chooseOutput()}.buttonStyle(.plain).foregroundStyle(Color.accent); Image(systemName:"chevron.down").font(.system(size:8)) }.font(.system(size:11)).disabled(model.running).help(model.outputDirectory)
                Text(model.running ? model.message : "结果另存为新文件").font(.system(size:10)).foregroundStyle(Color.muted)
            }
            Spacer()
            if model.running {
                ProgressView(value:model.progress).frame(width:120).tint(.accent)
                Button("取消",action:model.cancel)
            } else {
                Button { model.run(store:store) } label: { HStack(spacing:9) { Text(tool.isAI ? "开始 AI 处理" : "开始处理"); Image(systemName:"arrow.right") } }.buttonStyle(PrimaryButtonStyle()).disabled(model.files.isEmpty && tool.id != "htmlToPDF")
            }
        }.padding(.horizontal,25).padding(.vertical,18).background(Color.white)
    }
}

struct OptionsEditor: View {
    let tool: PDFTool
    @Binding var values: [String:String]
    var body: some View {
        VStack(alignment:.leading,spacing:17) { ForEach(tool.options.filter(visible)) { option in
            VStack(alignment:.leading,spacing:7) {
                if option.kind != "toggle" { Text(option.label).font(.system(size:11,weight:.medium)) }
                switch option.kind {
                case "choice": Picker(option.label,selection:binding(option)) { ForEach(option.choices,id:\.value) { Text($0.label).tag($0.value) } }.labelsHidden().frame(maxWidth:.infinity,alignment:.leading)
                case "toggle": Toggle(option.label,isOn:Binding(get:{values[option.key,default:option.default] == "true"},set:{values[option.key] = $0 ? "true" : "false"})).font(.system(size:11)).toggleStyle(.checkbox)
                case "secret": SecureField(option.label,text:binding(option)).textFieldStyle(.roundedBorder)
                case "multiline": TextEditor(text:binding(option)).font(.system(size:12)).frame(height:70).padding(5).overlay(RoundedRectangle(cornerRadius:6).stroke(Color.black.opacity(0.15)))
                case "file":
                    HStack { Button("选择…") { let panel = NSOpenPanel(); if panel.runModal() == .OK {values[option.key] = panel.url?.path ?? ""} }; Text(values[option.key,default:""].isEmpty ? "未选择" : URL(fileURLWithPath:values[option.key,default:""]).lastPathComponent).font(.system(size:10)).lineLimit(1).foregroundStyle(Color.muted); if !values[option.key,default:""].isEmpty {Button {values[option.key] = ""} label:{Image(systemName:"xmark")}.buttonStyle(.plain)} }
                case "color": HStack { RoundedRectangle(cornerRadius:4).fill(Color(hex:values[option.key,default:option.default])).frame(width:24,height:24); TextField(option.label,text:binding(option)).textFieldStyle(.roundedBorder) }
                default: TextField(option.label,text:binding(option)).textFieldStyle(.roundedBorder)
                }
                if !option.help.isEmpty { Text(option.help).font(.system(size:9.5)).foregroundStyle(Color.muted).fixedSize(horizontal:false,vertical:true) }
            }
        } }
    }
    func binding(_ o:ToolOption)->Binding<String> { Binding(get:{values[o.key,default:o.default]},set:{values[o.key] = $0}) }
    func visible(_ option:ToolOption)->Bool {
        if tool.id == "split",option.key == "groupSize" { return values["splitMode"] == "size" }
        if tool.id == "forms",["fieldName","fieldType","choices","fieldValue"].contains(option.key) { return values["formMode"] == "create" }
        if tool.id == "sign" {
            let certificate = values["signMode"] == "certificate"
            if ["certificate","certPassword","reason"].contains(option.key) {return certificate}
            if ["text","imagePath","fontSize","editMode","pages"].contains(option.key) {return !certificate}
        }
        if tool.id == "edit" {
            if option.key == "text" || option.key == "fontSize" {return values["editMode"] == "text"}
            if option.key == "imagePath" {return values["editMode"] == "image"}
        }
        return true
    }
}
