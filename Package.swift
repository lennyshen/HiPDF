// swift-tools-version: 5.9
import PackageDescription
let package = Package(name:"HiPDF",platforms:[.macOS(.v14)],products:[.executable(name:"HiPDF",targets:["HiPDF"]),.executable(name:"HiPDFOCR",targets:["HiPDFOCR"])],targets:[.executableTarget(name:"HiPDF"),.executableTarget(name:"HiPDFOCR")])
