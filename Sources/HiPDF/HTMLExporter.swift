import Foundation
import AppKit
import WebKit
import PDFKit

@MainActor final class HTMLExporter: NSObject, WKNavigationDelegate {
    private var web: WKWebView?
    private var continuation: CheckedContinuation<[URL],Error>?
    private var options: [String:String] = [:]
    private var folder: URL?
    private var timeout: Task<Void,Never>?
    func export(source:URL?,options:[String:String],outputDirectory:String) async throws -> [URL] {
        self.options = options
        let destination = URL(fileURLWithPath:outputDirectory).appendingPathComponent("HiPDF-网页-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]); folder = destination
        return try await withCheckedThrowingContinuation { completion in
            continuation = completion
            let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
            var size = options["paper"] == "letter" ? NSSize(width:612,height:792) : NSSize(width:595,height:842)
            if options["landscape"] == "true" { size = NSSize(width:size.height,height:size.width) }
            let view = WKWebView(frame:NSRect(x:0,y:0,width:size.width-56,height:size.height-56),configuration:config)
            view.navigationDelegate = self; web = view
            if let source {view.loadFileURL(source,allowingReadAccessTo:source.deletingLastPathComponent())}
            else if let url = URL(string:options["url",default:""]),["http","https"].contains(url.scheme ?? "") {view.load(URLRequest(url:url,timeoutInterval:45))}
            else {finish(.failure(EngineError(message:"请输入有效的 HTTP(S) 网页地址，或选择 HTML 文件。")));return}
            timeout = Task {try? await Task.sleep(nanoseconds:60_000_000_000);if !Task.isCancelled {finish(.failure(EngineError(message:"网页加载超时。")))}}
        }
    }
    func cancel() {web?.stopLoading();finish(.failure(EngineError(message:"任务已取消。")))}
    func webView(_ webView:WKWebView,didFail navigation:WKNavigation!,withError error:Error) {finish(.failure(EngineError(message:"网页加载失败。")))}
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) {finish(.failure(EngineError(message:"无法访问网页，请检查地址和网络。")))}
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) {
        Task { @MainActor in
            _ = try? await webView.callAsyncJavaScript("await document.fonts.ready; return true;",arguments:[:],in:nil,contentWorld:.page)
            guard continuation != nil,let folder else {return}
            let output = folder.appendingPathComponent("网页.pdf")
            do {
                let layout = try await webView.evaluateJavaScript("""
                (() => {
                  const height=Math.max(document.body.scrollHeight,document.documentElement.scrollHeight);
                  const lines=[]; const breaks=[];
                  const walker=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT);
                  while(walker.nextNode()) { const node=walker.currentNode; if(!node.textContent.trim())continue;
                    const range=document.createRange();range.selectNodeContents(node);
                    for(const r of range.getClientRects())if(r.height>0&&r.height<120)lines.push([r.top+scrollY,r.bottom+scrollY]);
                  }
                  for(const el of document.querySelectorAll('body *')) { const s=getComputedStyle(el),r=el.getBoundingClientRect();
                    if(['page','always'].includes(s.breakBefore))breaks.push(r.top+scrollY);
                    if(['page','always'].includes(s.breakAfter))breaks.push(r.bottom+scrollY);
                  }
                  return {height,lines,breaks};
                })()
                """) as? [String:Any] ?? [:]
                let height = layout["height"] as? Double ?? Double(webView.bounds.height)
                guard height.isFinite,height>0,height<1_000_000 else {throw EngineError(message:"网页过长，无法一次导出。")}
                let lineRects = layout["lines"] as? [[Double]] ?? []
                let hardBreaks = (layout["breaks"] as? [Double] ?? []).sorted()
                let pageWidth = webView.bounds.width, pageHeight = webView.bounds.height
                var media = CGRect(x:0,y:0,width:pageWidth+56,height:pageHeight+56)
                guard let consumer = CGDataConsumer(url:output as CFURL),let context = CGContext(consumer:consumer,mediaBox:&media,nil) else {throw EngineError(message:"无法创建 PDF 输出。")}
                var top: CGFloat = 0
                while top < height-0.5 {
                    guard continuation != nil else {context.closePDF();return}
                    var end = min(height,top+pageHeight)
                    if let forced = hardBreaks.first(where:{$0>top+1 && $0<=end}) {end = forced}
                    for line in lineRects where line.count == 2 && line[0] < end && line[1] > end && line[0] > top+60 {end = min(end,line[0])}
                    let configuration = WKPDFConfiguration()
                    configuration.rect = CGRect(x:0,y:top,width:pageWidth,height:max(1,end-top))
                    let data = try await webView.pdf(configuration:configuration)
                    guard let fragment = PDFDocument(data:data)?.page(at:0) else {throw EngineError(message:"网页页面生成失败。")}
                    context.beginPDFPage(nil)
                    context.saveGState()
                    context.translateBy(x:28,y:28+pageHeight-(end-top))
                    fragment.draw(with:.mediaBox,to:context)
                    context.restoreGState();context.endPDFPage()
                    top = end
                }
                context.closePDF()
                guard let doc = PDFDocument(url:output),doc.pageCount>0 else {throw EngineError(message:"网页 PDF 导出失败。")}
                finish(.success([output]))
            } catch {finish(.failure(error))}
        }
    }
    private func finish(_ result:Result<[URL],Error>) {
        guard let completion = continuation else {return};continuation = nil
        timeout?.cancel();timeout = nil
        if case .failure = result,let folder {try? FileManager.default.removeItem(at:folder)}
        web?.navigationDelegate = nil;web = nil;folder = nil
        completion.resume(with:result)
    }
}
