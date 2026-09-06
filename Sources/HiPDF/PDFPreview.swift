import SwiftUI
import PDFKit

struct PDFPreviewPane: View {
    var url: URL
    var password: String
    var selectable: Bool
    var tool: PDFTool
    @Binding var options: [String:String]
    @Binding var regions: [PageRegion]
    var isResult: Bool
    var onLoaded: (Int) -> Void = { _ in }
    @State private var document: PDFDocument?
    @State private var loading = true
    @State private var failure: PDFLoadFailure?
    @State private var reload = 0
    @State private var pageIndex = 0
    @State private var zoom: CGFloat = 0
    @State private var capture = true
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:10) {
                Image(systemName:isResult ? "checkmark.circle" : "doc.text.magnifyingglass").foregroundStyle(Color.accent)
                Text(isResult ? "结果预览" : "文档预览").font(.system(size:11,weight:.medium))
                Spacer()
                if tool.canDraw && selectable { Toggle("\(options["editMode"] == "ink" ? "手绘" : "框选")",isOn:$capture).font(.system(size:10)).toggleStyle(.checkbox) }
                Button { zoom = max(0.25,zoom == 0 ? 0.8 : zoom-0.15) } label:{Image(systemName:"minus.magnifyingglass")}.help("缩小")
                Button { zoom = min(4,zoom == 0 ? 1.2 : zoom+0.15) } label:{Image(systemName:"plus.magnifyingglass")}.help("放大")
                Button { zoom = 0 } label:{Image(systemName:"arrow.up.left.and.arrow.down.right")}.help("适合页面")
            }.font(.system(size:12)).buttonStyle(.plain).padding(.horizontal,17).frame(height:43).background(Color(hex:"F0F2ED"))
            if loading {
                VStack(spacing:14) { ProgressView(); Text("正在读取 PDF…").font(.system(size:13)); Text("云盘文件可能需要先下载到本机。").font(.system(size:11)).foregroundStyle(Color.muted) }
                    .frame(maxWidth:.infinity,maxHeight:.infinity)
            } else if let doc = document,!doc.isLocked {
                HStack(spacing:0) {
                    ScrollView {
                        LazyVStack(spacing:14) {
                            ForEach(0..<doc.pageCount,id:\.self) { index in
                                if let page = doc.page(at:index) {
                                    VStack(spacing:5) {
                                        Button {pageIndex = index} label: {
                                            Image(nsImage:page.thumbnail(of:NSSize(width:66,height:92),for:.cropBox)).resizable().scaledToFit().frame(width:66,height:92)
                                                .background(Color.white).overlay(RoundedRectangle(cornerRadius:2).stroke(index == pageIndex ? Color.accent : Color.black.opacity(0.08),lineWidth:index == pageIndex ? 2 : 1))
                                        }.buttonStyle(.plain)
                                        HStack(spacing:5) {
                                            if selectable && tool.options.contains(where:{$0.key == "pages"}) {
                                                Button {togglePage(index+1)} label:{Image(systemName:selectedPages.contains(index+1) ? "checkmark.square.fill" : "square").foregroundStyle(selectedPages.contains(index+1) ? Color.accent : Color.muted)}.buttonStyle(.plain).help("选择第 \(index+1) 页")
                                            }
                                            Text("\(index+1)").foregroundStyle(Color.muted)
                                        }.font(.system(size:9))
                                    }
                                }
                            }
                        }.padding(.vertical,17)
                    }.frame(width:94).background(Color(hex:"EBEEE8"))
                    PDFCanvas(document:doc,pageIndex:$pageIndex,zoom:zoom,capture:tool.canDraw && selectable && capture,
                              mode:options["editMode"] == "ink" ? "ink" : tool.id,text:options["text",default:""],regions:regions) { region in
                        var region = region
                        region.mode = options["editMode",default:tool.id]
                        regions.append(region)
                    }
                }
                HStack { Text("\(doc.pageCount) 页"); Spacer(); if selectable {Text(tool.canDraw ? "拖动选择区域 · 原件不会被修改" : "点击页面预览，勾选页码选择范围")} }.font(.system(size:9.5)).foregroundStyle(Color.muted).padding(.horizontal,16).frame(height:29).background(Color(hex:"F0F2ED"))
            } else {
                ContentUnavailableView {
                    Label(failure?.title ?? "无法预览此 PDF",systemImage:failure?.kind == .password ? "lock.doc" : "doc.badge.exclamationmark")
                } description: {
                    Text(failure?.message ?? "请重新加载或选择其他文件。")
                } actions: {
                    Button("重新加载") { reload += 1 }
                    Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
            }
        }
        .task(id:LoadIdentity(url:url,password:password,reload:reload)) {
            loading = true; document = nil; failure = nil; pageIndex = 0; zoom = 0
            do {
                let loaded = try await PDFLoader.load(url,password:password)
                try Task.checkCancellation()
                document = loaded.document; loading = false; onLoaded(loaded.document.pageCount)
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled else { return }
                failure = error as? PDFLoadFailure ?? PDFLoadFailure(kind:.unreadable,message:error.localizedDescription)
                loading = false
            }
        }
    }
    private struct LoadIdentity: Hashable { let url:URL; let password:String; let reload:Int }
    var selectedPages: [Int] {
        let spec = options["pages",default:""].replacingOccurrences(of:"，",with:",")
        return spec.split(separator:",").flatMap { item -> [Int] in
            let parts = item.trimmingCharacters(in:.whitespaces).split(separator:"-").compactMap {Int($0)}
            if parts.count == 1 {return parts}
            if parts.count == 2,abs(parts[1]-parts[0])<100000 {return Array(stride(from:parts[0],through:parts[1],by:parts[1]>=parts[0] ? 1 : -1))}
            return []
        }
    }
    func togglePage(_ page:Int) {
        var list = selectedPages
        if list.contains(page) {list.removeAll {$0 == page}} else {list.append(page)}
        if tool.id != "organize" {list.sort()}
        options["pages"] = list.map(String.init).joined(separator:",")
    }
}

struct PDFCanvas: NSViewRepresentable {
    var document: PDFDocument
    @Binding var pageIndex: Int
    var zoom: CGFloat
    var capture: Bool
    var mode: String
    var text: String
    var regions: [PageRegion]
    var onRegion: (PageRegion)->Void
    func makeNSView(context:Context)->InteractivePDFView {
        let view = InteractivePDFView()
        view.displayMode = .singlePageContinuous; view.displayDirection = .vertical; view.autoScales = true
        view.backgroundColor = NSColor(Color(hex:"E4E8E0")); view.displaysPageBreaks = true
        view.onRegion = onRegion
        context.coordinator.observer = NotificationCenter.default.addObserver(forName:.PDFViewPageChanged,object:view,queue:.main) { [weak view] _ in
            if let doc = view?.document,let page = view?.currentPage { let index = doc.index(for:page); if index != context.coordinator.lastPage {context.coordinator.lastPage = index; DispatchQueue.main.async {pageIndex = index}} }
        }
        return view
    }
    func updateNSView(_ view:InteractivePDFView,context:Context) {
        if view.document !== document {view.document = document;view.autoScales = true}
        if context.coordinator.lastPage != pageIndex,let page = document.page(at:pageIndex) { context.coordinator.lastPage = pageIndex; view.go(to:page) }
        if zoom == 0 {view.autoScales = true} else {view.autoScales = false;view.scaleFactor = zoom}
        view.capture = capture; view.drawingMode = mode; view.labelText = text; view.onRegion = onRegion
        let signature = regions.map { $0.id.uuidString }.joined()
        if view.regionSignature != signature { view.regionSignature = signature; view.show(regions) }
    }
    func makeCoordinator()->Coordinator {Coordinator()}
    static func dismantleNSView(_ view:InteractivePDFView,coordinator:Coordinator) { if let observer = coordinator.observer {NotificationCenter.default.removeObserver(observer)} }
    final class Coordinator {var observer: NSObjectProtocol?;var lastPage = -1}
}

final class InteractivePDFView: PDFView {
    var capture = false
    var drawingMode = "edit"
    var labelText = ""
    var onRegion: ((PageRegion)->Void)?
    var regionSignature = ""
    private var start: CGPoint?
    private var startPage: PDFPage?
    private var ink: [[Double]] = []
    private var temporary: PDFAnnotation?
    private var previews: [(PDFPage,PDFAnnotation)] = []
    override func mouseDown(with event:NSEvent) {
        guard capture else {super.mouseDown(with:event);return}
        let location = convert(event.locationInWindow,from:nil)
        guard let page = page(for:location,nearest:false) else {return}
        start = convert(location,to:page); startPage = page; ink = []
        if let start { ink.append(normalize(start,page:page)) }
    }
    override func mouseDragged(with event:NSEvent) {
        guard capture,let start,let page = startPage else {super.mouseDragged(with:event);return}
        let point = convert(convert(event.locationInWindow,from:nil),to:page)
        if let temporary {page.removeAnnotation(temporary)}
        let bounds = CGRect(x:min(start.x,point.x),y:min(start.y,point.y),width:abs(start.x-point.x),height:abs(start.y-point.y))
        let annotation = PDFAnnotation(bounds:bounds,forType:.square,withProperties:nil)
        annotation.color = drawingMode == "redact" ? .systemRed : NSColor(Color.accent)
        annotation.interiorColor = annotation.color.withAlphaComponent(0.12)
        page.addAnnotation(annotation); temporary = annotation
        if drawingMode == "ink" {ink.append(normalize(point,page:page))}
        annotationsChanged(on:page)
    }
    override func mouseUp(with event:NSEvent) {
        guard capture,let start,let page = startPage else {super.mouseUp(with:event);return}
        defer {self.start = nil;startPage = nil;temporary = nil}
        if let temporary {page.removeAnnotation(temporary)}
        let end = convert(convert(event.locationInWindow,from:nil),to:page)
        var a = normalize(start,page:page); var b = normalize(end,page:page)
        if drawingMode == "ink",!ink.isEmpty {
            a = [ink.map {$0[0]}.min() ?? a[0],ink.map {$0[1]}.min() ?? a[1]]
            b = [ink.map {$0[0]}.max() ?? b[0],ink.map {$0[1]}.max() ?? b[1]]
        }
        let rect = [min(a[0],b[0]),min(a[1],b[1]),max(a[0],b[0]),max(a[1],b[1])]
        guard rect[2]-rect[0]>0.003,rect[3]-rect[1]>0.003,let document else {return}
        onRegion?(.init(page:document.index(for:page),rect:rect,mode:drawingMode,text:labelText,points:ink))
    }
    func normalize(_ point:CGPoint,page:PDFPage)->[Double] {
        let r = page.bounds(for:.cropBox)
        return [min(1,max(0,(point.x-r.minX)/r.width)),min(1,max(0,1-(point.y-r.minY)/r.height))]
    }
    func show(_ regions:[PageRegion]) {
        for (page,annotation) in previews {page.removeAnnotation(annotation)}
        previews = []
        for region in regions {
            guard let page = document?.page(at:region.page) else {continue}
            let r = page.bounds(for:.cropBox);let v = region.rect
            let rect = CGRect(x:r.minX+v[0]*r.width,y:r.minY+(1-v[3])*r.height,width:(v[2]-v[0])*r.width,height:(v[3]-v[1])*r.height)
            let annotation = PDFAnnotation(bounds:rect,forType:.square,withProperties:nil)
            annotation.color = region.mode == "redact" ? .systemRed : NSColor(Color.accent)
            annotation.interiorColor = annotation.color.withAlphaComponent(0.10)
            page.addAnnotation(annotation);previews.append((page,annotation));annotationsChanged(on:page)
        }
    }
}
