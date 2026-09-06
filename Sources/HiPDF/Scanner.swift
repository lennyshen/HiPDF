import SwiftUI
import Quartz
import ImageCaptureCore

@MainActor final class ScannerController: NSObject, ObservableObject, @preconcurrency ICDeviceBrowserDelegate, @preconcurrency IKScannerDeviceViewDelegate {
    @Published var devices: [ICScannerDevice] = []
    @Published var selected: String = ""
    @Published var scans: [URL] = []
    @Published var message = "正在查找已连接的扫描仪…"
    private let browser = ICDeviceBrowser()
    let folder: URL
    override init() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("HiPDF-Scans-\(UUID().uuidString)")
        super.init()
        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        browser.delegate = self
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue:ICDeviceTypeMask.scanner.rawValue | ICDeviceLocationTypeMask.local.rawValue | ICDeviceLocationTypeMask.shared.rawValue)!
        browser.start()
    }
    func stop() {browser.stop()}
    func deviceBrowser(_ browser:ICDeviceBrowser,didAdd device:ICDevice,moreComing:Bool) {
        if let scanner = device as? ICScannerDevice {devices.append(scanner);if selected.isEmpty {selected = scanner.uuidString ?? scanner.name ?? ""};message = "选择设备后，可直接预览和扫描。"}
    }
    func deviceBrowser(_ browser:ICDeviceBrowser,didRemove device:ICDevice,moreGoing:Bool) {devices.removeAll {$0 === device}}
    func scannerDeviceView(_ scannerDeviceView:IKScannerDeviceView!,didScanTo url:URL!,fileData data:Data!,error:Error!) {
        if let error {message = error.localizedDescription;return}
        if let url {scans.append(url)} else if let data {let path = folder.appendingPathComponent("扫描-\(scans.count+1).tiff");do {try data.write(to:path);scans.append(path)} catch {message = error.localizedDescription}}
        message = "已扫描 \(scans.count) 张图像。"
    }
    func scannerDeviceView(_ scannerDeviceView:IKScannerDeviceView!,didEncounterError error:Error!) {message = error?.localizedDescription ?? "扫描仪出现错误。"}
}

struct ScannerSheet: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var controller = ScannerController()
    var onImport:([URL])->Void
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {Text("扫描到 HiPDF").font(.system(size:23,weight:.semibold));Spacer();Button("关闭") {dismiss()}}
            if controller.devices.isEmpty {ContentUnavailableView("未发现扫描仪",systemImage:"scanner",description:Text("连接兼容 macOS 图像捕捉的扫描仪并打开电源。\n也可以返回工具页，导入相机或 iPhone 扫描图片。"))}
            else {
                Picker("扫描仪",selection:$controller.selected) {ForEach(controller.devices,id:\.self) {device in Text(device.name ?? "扫描仪").tag(device.uuidString ?? device.name ?? "")}}
                ScannerDeviceView(controller:controller).frame(maxHeight:.infinity)
            }
            HStack {Text(controller.message).font(.system(size:11)).foregroundStyle(Color.muted);Spacer();Button("导入 \(controller.scans.count) 张图像") {onImport(controller.scans)}.buttonStyle(PrimaryButtonStyle()).disabled(controller.scans.isEmpty)}
        }.padding(25).frame(width:820,height:650).onDisappear {controller.stop()}
    }
}
struct ScannerDeviceView: NSViewRepresentable {
    @ObservedObject var controller: ScannerController
    func makeNSView(context:Context)->IKScannerDeviceView {
        let view = IKScannerDeviceView()
        view.delegate = controller;view.mode = .advanced;view.transferMode = .fileBased;view.downloadsDirectory = controller.folder
        view.displaysPostProcessApplicationControl = false;view.displaysDownloadsDirectoryControl = false
        return view
    }
    func updateNSView(_ view:IKScannerDeviceView,context:Context) {
        view.scannerDevice = controller.devices.first {($0.uuidString ?? $0.name ?? "") == controller.selected}
    }
}
