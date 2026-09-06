import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DashboardView: View {
    @EnvironmentObject var store: AppStore
    @FocusState private var searchFocused: Bool
    @State private var dropping = false
    var filtered: [PDFTool] {
        store.tools.filter { tool in
            let routeMatch = store.route == "home" || (store.route == "favorites" ? store.favorites.contains(tool.id) : store.route == tool.category)
            return routeMatch && (store.query.isEmpty || (tool.name+tool.subtitle+tool.id).localizedCaseInsensitiveContains(store.query))
        }
    }
    var heading: String { store.route == "favorites" ? "我的收藏" : Category.all.first(where:{$0.id == store.route})?.name ?? "所有工具" }
    var body: some View {
        VStack(spacing:0) {
            HStack {
                HStack(spacing:7) { Image(systemName:"square.grid.2x2.fill").font(.system(size:12)); Text("你的 PDF 工作空间").font(.system(size:12,weight:.medium)) }.foregroundStyle(Color.muted)
                Spacer()
                HStack(spacing:8) {
                    Image(systemName:"magnifyingglass").foregroundStyle(Color.muted)
                    TextField("搜索工具…",text:$store.query).textFieldStyle(.plain).focused($searchFocused).font(.system(size:12))
                    Text("⌘ K").font(.system(size:10)).foregroundStyle(Color.muted)
                }.padding(.horizontal,12).frame(width:235,height:34).background(.white,in:RoundedRectangle(cornerRadius:9))
                Button { store.showSettings = true } label: { Image(systemName:"slider.horizontal.3").font(.system(size:16)).foregroundStyle(Color.muted).frame(width:34,height:34) }.buttonStyle(.plain).help("设置")
            }.padding(.horizontal,34).padding(.top,28).padding(.bottom,22)
            ScrollView {
                VStack(alignment:.leading,spacing:27) {
                    if store.route == "home" && store.query.isEmpty {
                        hero
                        favorites
                    }
                    HStack(alignment:.firstTextBaseline) {
                        Text(heading).font(.system(size:20,weight:.semibold)).tracking(-0.4)
                        Text("\(filtered.count) 个工具").font(.system(size:11)).foregroundStyle(Color.muted)
                        Spacer()
                        if store.route == "home" { Text("从整理到创作，每一步都顺手。").font(.system(size:11)).foregroundStyle(Color.muted) }
                    }
                    if filtered.isEmpty {
                        ContentUnavailableView(store.route == "favorites" ? "收藏你常用的工具" : "没有找到工具",systemImage:"magnifyingglass",description:Text("试试搜索「合并」「翻译」或「Word」。"))
                    } else {
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:220,maximum:360),spacing:14)],spacing:14) {
                            ForEach(filtered) { ToolCard(tool:$0) }
                        }
                    }
                    HStack(spacing:6) {
                        Image(systemName:"leaf").foregroundStyle(Color.accent)
                        Text("为你的 Mac 而生。让每一份文档，各得其所。").foregroundStyle(Color.muted)
                        Spacer(); Text("HiPDF 1.0").foregroundStyle(Color.muted.opacity(0.7))
                    }.font(.system(size:10)).padding(.top,4).padding(.bottom,24)
                }.padding(.horizontal,34)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for:.hipdfSearch)) { _ in searchFocused = true }
        .onReceive(NotificationCenter.default.publisher(for:.hipdfOpen)) { _ in if store.currentTool == nil { chooseDocuments() } }
        .onDrop(of:[UTType.fileURL.identifier],isTargeted:$dropping) { providers in
            collectDroppedURLs(providers) { urls in if let tool = store.tools.first(where:{$0.id == "organize"}) { store.open(tool,files:urls) } }; return true
        }
        .overlay { if dropping { RoundedRectangle(cornerRadius:20).stroke(Color.accent,style:StrokeStyle(lineWidth:3,dash:[8])).padding(12).allowsHitTesting(false) } }
    }
    var hero: some View {
        HStack(spacing:20) {
            VStack(alignment:.leading,spacing:14) {
                HStack(spacing:6) { Circle().fill(Color(hex:"B6D6AB")).frame(width:5,height:5); Text("GOOD DOCUMENTS. BETTER DAYS.").font(.system(size:8.5,weight:.semibold)).tracking(2.1).foregroundStyle(Color(hex:"C0D7C4")) }
                Text("让文档工作，\n轻一点。").font(.system(size:34,weight:.semibold)).tracking(-1).lineSpacing(3).foregroundStyle(Color(hex:"F5F6E9"))
                Text("33 个实用工具，一个安静高效的工作空间。\n整理、转换、签署，和文档的更多可能。").font(.system(size:11.5)).lineSpacing(5).foregroundStyle(Color(hex:"BDCEC0"))
                Button(action:chooseDocuments) { HStack(spacing:8) { Image(systemName:"plus"); Text("打开文件，开始工作"); Image(systemName:"arrow.up.right").font(.system(size:10)) }.font(.system(size:11,weight:.semibold)).foregroundStyle(Color(hex:"214D3D")).padding(.horizontal,15).padding(.vertical,10).background(Color(hex:"E8EDCD"),in:RoundedRectangle(cornerRadius:8)) }.buttonStyle(.plain).padding(.top,2)
            }
            Spacer(minLength:0)
            DocumentIllustration().frame(width:260,height:225).padding(.trailing,10)
        }.padding(.vertical,27).padding(.horizontal,32)
            .frame(maxWidth:.infinity,alignment:.leading)
            .background(LinearGradient(colors:[Color(hex:"284D3D"),Color(hex:"366B56")],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:19))
    }
    var favorites: some View {
        VStack(alignment:.leading,spacing:13) {
            HStack { SmallLabel(title:"常用工具"); Spacer(); Button("查看收藏 →") { store.route = "favorites" }.font(.system(size:10)).foregroundStyle(Color.accent).buttonStyle(.plain) }
            LazyVGrid(columns:[GridItem(.adaptive(minimum:155),spacing:12)],spacing:12) {
                ForEach(store.tools.filter { store.favorites.contains($0.id) }.prefix(4)) { tool in
                    Button { store.open(tool) } label: {
                        HStack(spacing:10) { ToolIcon(tool:tool,size:32); Text(tool.name).font(.system(size:11.5,weight:.medium)); Spacer(minLength:0); Image(systemName:"arrow.up.right").font(.system(size:9)).foregroundStyle(Color.muted) }.padding(12).background(Color.white,in:RoundedRectangle(cornerRadius:11)).overlay(RoundedRectangle(cornerRadius:11).stroke(Color.black.opacity(0.04)))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    func chooseDocuments() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.pdf]; panel.allowsMultipleSelection = true
        if panel.runModal() == .OK, let tool = store.tools.first(where:{$0.id == "organize"}) { store.open(tool,files:panel.urls) }
    }
}

struct ToolCard: View {
    @EnvironmentObject var store: AppStore
    let tool: PDFTool
    @State private var hovered = false
    var body: some View {
        Button { store.open(tool) } label: {
            VStack(alignment:.leading,spacing:13) {
                HStack(alignment:.top) {
                    ToolIcon(tool:tool)
                    Spacer()
                    if tool.isAI { Text("AI").font(.system(size:9,weight:.semibold)).foregroundStyle(Color.accent).padding(.horizontal,6).padding(.vertical,4).background(Color.accent.opacity(0.08),in:Capsule()) }
                    Button { store.toggleFavorite(tool.id) } label: {
                        Image(systemName:store.favorites.contains(tool.id) ? "star.fill" : "star").font(.system(size:11)).foregroundStyle(store.favorites.contains(tool.id) ? Color(hex:"C7A66D") : Color.muted.opacity(hovered ? 0.8 : 0.3)).frame(width:19,height:22)
                    }.buttonStyle(.plain).help("收藏 \(tool.name)")
                }
                VStack(alignment:.leading,spacing:7) {
                    Text(tool.name).font(.system(size:14,weight:.semibold)).foregroundStyle(Color.ink)
                    Text(tool.subtitle).font(.system(size:11)).foregroundStyle(Color.muted).lineLimit(1)
                }
            }.padding(19).frame(maxWidth:.infinity,alignment:.leading).frame(height:143)
                .background(Color.white,in:RoundedRectangle(cornerRadius:13))
                .overlay(RoundedRectangle(cornerRadius:13).stroke(hovered ? tool.tint.opacity(0.55) : Color.black.opacity(0.055),lineWidth:1))
                .shadow(color:Color.accent.opacity(hovered ? 0.06 : 0),radius:9,y:4)
        }.buttonStyle(.plain).onHover { hovered = $0 }.animation(.easeOut(duration:0.15),value:hovered)
    }
}

struct DocumentIllustration: View {
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.07),lineWidth:1).frame(width:218,height:218)
            Circle().stroke(Color.white.opacity(0.06),lineWidth:1).frame(width:285,height:285)
            RoundedRectangle(cornerRadius:12).fill(Color(hex:"81A18C")).frame(width:139,height:177).rotationEffect(.degrees(-17)).offset(x:-23,y:4)
            RoundedRectangle(cornerRadius:12).fill(Color(hex:"C8D1B1")).frame(width:139,height:177).rotationEffect(.degrees(9)).offset(x:19,y:3)
            VStack(alignment:.leading,spacing:12) {
                HStack { Text("PDF").font(.system(size:10,weight:.bold,design:.rounded)).tracking(1); Spacer(); Image(systemName:"leaf.fill").font(.system(size:15)).foregroundStyle(Color.accent) }.foregroundStyle(Color.accent)
                RoundedRectangle(cornerRadius:2).fill(Color(hex:"CED5C6")).frame(width:75,height:5).padding(.top,8)
                ForEach(0..<4) { i in RoundedRectangle(cornerRadius:2).fill(Color(hex:"E0E5D8")).frame(width:i == 3 ? 57 : 91,height:4) }
                Spacer()
                HStack(spacing:6) { Image(systemName:"checkmark.circle.fill").foregroundStyle(Color.accent); Text("Made simple.").font(.system(size:7.5)).foregroundStyle(Color.muted) }
            }.padding(20).frame(width:139,height:177).background(Color(hex:"F8F7EB"),in:RoundedRectangle(cornerRadius:10)).rotationEffect(.degrees(-3)).shadow(color:.black.opacity(0.15),radius:13,y:10)
            Image(systemName:"sparkles").font(.system(size:18)).foregroundStyle(Color(hex:"D9E5AB")).offset(x:99,y:-91)
            HStack(spacing:7) { Image(systemName:"checkmark.shield.fill"); Text("只在本机").font(.system(size:10,weight:.medium)) }.foregroundStyle(Color(hex:"325641")).padding(.horizontal,12).padding(.vertical,9).background(Color(hex:"E3EACB"),in:Capsule()).rotationEffect(.degrees(-6)).offset(x:64,y:83)
        }
    }
}

func collectDroppedURLs(_ providers: [NSItemProvider],completion:@escaping @MainActor ([URL])->Void) {
    let group = DispatchGroup(); let lock = NSLock(); var items: [(Int,URL)] = []
    for (index,provider) in providers.enumerated() {
        group.enter()
        provider.loadItem(forTypeIdentifier:UTType.fileURL.identifier,options:nil) { item,_ in
            var url: URL?
            if let data = item as? Data { url = URL(dataRepresentation:data,relativeTo:nil) }
            else if let item = item as? URL { url = item }
            if let url { lock.lock(); items.append((index,url)); lock.unlock() }
            group.leave()
        }
    }
    group.notify(queue:.main) { Task { @MainActor in completion(items.sorted {$0.0 < $1.0}.map(\.1)) } }
}

struct HistoryView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        VStack(alignment:.leading,spacing:24) {
            HStack { VStack(alignment:.leading,spacing:7) { Text("最近任务").font(.system(size:27,weight:.semibold)); Text("每次处理都有独立的结果，原文件始终保留。").font(.system(size:12)).foregroundStyle(Color.muted) }; Spacer(); Button("清空记录") { store.history = [] }.disabled(store.history.isEmpty).help("只移除历史记录，保留磁盘上的输出文件") }
            if store.history.isEmpty { ContentUnavailableView("还没有处理记录",systemImage:"clock",description:Text("完成一次文档处理后，结果会出现在这里。")) }
            else {
                List(store.history) { item in
                    HStack(spacing:14) {
                        if let tool = store.tools.first(where:{$0.id == item.tool}) { ToolIcon(tool:tool,size:36) }
                        VStack(alignment:.leading,spacing:5) { Text(store.tools.first(where:{$0.id == item.tool})?.name ?? "工作流程").font(.system(size:13,weight:.medium)); Text("\(item.count) 个输入 · \(item.outputs.count) 个结果 · \(item.date.formatted(date:.abbreviated,time:.shortened))").font(.system(size:11)).foregroundStyle(Color.muted) }
                        Spacer(); Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting(item.outputs.map { URL(fileURLWithPath:$0) }) }
                    }.padding(.vertical,10)
                }.listStyle(.plain).scrollContentBackground(.hidden)
            }
            Spacer()
        }.padding(34).padding(.top,28)
    }
}
