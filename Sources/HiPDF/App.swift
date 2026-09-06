import SwiftUI
import AppKit

@main struct HiPDFApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).frame(minWidth:1080,minHeight:720)
                .preferredColorScheme(.light).tint(.accent)
                .onOpenURL { url in
                    if let tool = store.tools.first(where: { $0.id == "organize" }) { store.open(tool,files:[url]) }
                }
        }
        .windowStyle(.hiddenTitleBar).defaultSize(width:1280,height:860)
        .commands {
            CommandGroup(replacing:.newItem) {
                Button("打开文件…") { NotificationCenter.default.post(name:.hipdfOpen,object:nil) }.keyboardShortcut("o")
            }
            CommandGroup(replacing:.appSettings) { Button("HiPDF 设置…") { store.showSettings = true }.keyboardShortcut(",") }
            CommandGroup(after:.pasteboard) { Button("查找工具") { store.currentTool = nil; store.route = "home"; NotificationCenter.default.post(name:.hipdfSearch,object:nil) }.keyboardShortcut("k") }
            CommandGroup(replacing:.help) { Button("HiPDF 使用说明") { let url = ResourceLocation.root.appendingPathComponent("USER_GUIDE.html"); NSWorkspace.shared.open(url) } }
        }
    }
}
extension Notification.Name {
    static let hipdfOpen = Notification.Name("hipdfOpen")
    static let hipdfSearch = Notification.Name("hipdfSearch")
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps:true) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct RootView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        HStack(spacing:0) {
            sidebar.frame(width:218)
            Rectangle().fill(Color.black.opacity(0.055)).frame(width:1)
            Group {
                if let tool = store.currentTool { WorkbenchView(tool:tool).id(tool.id) }
                else if store.route == "history" { HistoryView() }
                else if store.route == "workflows" { WorkflowView() }
                else { DashboardView() }
            }.frame(maxWidth:.infinity,maxHeight:.infinity).background(Color.canvas)
        }
        .foregroundStyle(Color.ink)
        .sheet(isPresented:$store.showSettings) { SettingsView() }
        .alert("HiPDF",isPresented:Binding(get:{store.catalogError != nil},set:{if !$0 {store.catalogError = nil}})) { Button("确定") {store.catalogError = nil} } message: { Text(store.catalogError ?? "") }
    }
    var sidebar: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:10) {
                ZStack {
                    RoundedRectangle(cornerRadius:11).fill(Color.accent).frame(width:36,height:36)
                    Image(systemName:"doc.fill").font(.system(size:22)).foregroundStyle(.white)
                    Text("h").font(.system(size:14,weight:.heavy,design:.rounded)).foregroundStyle(Color.accent).offset(y:2)
                }
                Text("HiPDF").font(.system(size:24,weight:.bold,design:.rounded)).tracking(-0.7)
                Text("MAC").font(.system(size:8,weight:.bold)).tracking(1).foregroundStyle(Color.muted).padding(.top,7)
            }.padding(.top,43).padding(.bottom,32).padding(.leading,22)
            VStack(spacing:5) {
                nav("home","工作台","square.grid.2x2")
                nav("favorites","我的收藏","star")
                nav("history","最近任务","clock.arrow.circlepath")
            }.padding(.horizontal,12)
            SmallLabel(title:"文档工具").padding(.leading,25).padding(.top,30).padding(.bottom,12)
            VStack(spacing:5) { ForEach(Category.all) { nav($0.id,$0.name,$0.icon) } }.padding(.horizontal,12)
            SmallLabel(title:"自动化").padding(.leading,25).padding(.top,28).padding(.bottom,12)
            nav("workflows","工作流程","point.3.connected.trianglepath.dotted").padding(.horizontal,12)
            Spacer(minLength:24)
            VStack(alignment:.leading,spacing:9) {
                HStack(spacing:7) { Image(systemName:"externaldrive.badge.checkmark"); Text("本地处理，安心使用").font(.system(size:11,weight:.medium)) }.foregroundStyle(Color.accent)
                Text("文件留在你的 Mac\nAI 服务由你选择与配置").font(.system(size:10)).foregroundStyle(Color.muted).lineSpacing(4)
            }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(Color.white.opacity(0.75),in:RoundedRectangle(cornerRadius:12)).padding(.horizontal,15)
            Button { store.showSettings = true } label: {
                HStack(spacing:10) { Image(systemName:"gearshape"); Text("设置"); Spacer(); Text("⌘ ,").font(.system(size:10)) }.font(.system(size:12)).foregroundStyle(Color.muted).padding(22)
            }.buttonStyle(.plain)
        }.background(Color(hex:"EEF2EC")).disabled(store.busy)
    }
    func nav(_ id:String,_ label:String,_ icon:String) -> some View {
        let selected = store.currentTool == nil && store.route == id
        return Button { store.route = id; store.currentTool = nil; store.query = "" } label: {
            HStack(spacing:12) { Image(systemName:icon).font(.system(size:14)).frame(width:18); Text(label).font(.system(size:12.5,weight:selected ? .semibold : .regular)); Spacer()
                if id == "ai" { Text("AI").font(.system(size:8,weight:.semibold)).padding(.horizontal,5).padding(.vertical,3).background(Color.accent.opacity(0.08),in:Capsule()) }
            }.foregroundStyle(selected ? Color.accent : Color(hex:"65756D")).padding(.horizontal,13).frame(height:39)
                .background(selected ? Color.white : Color.clear,in:RoundedRectangle(cornerRadius:9))
        }.buttonStyle(.plain)
    }
}
