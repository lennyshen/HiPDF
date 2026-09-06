import AppKit
import Foundation
let output = URL(fileURLWithPath:CommandLine.arguments.count>1 ? CommandLine.arguments[1] : "Resources")
let folder = output.appendingPathComponent("HiPDF.iconset")
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
for (size,name) in [(16,"icon_16x16"),(32,"icon_16x16@2x"),(32,"icon_32x32"),(64,"icon_32x32@2x"),(128,"icon_128x128"),(256,"icon_128x128@2x"),(256,"icon_256x256"),(512,"icon_256x256@2x"),(512,"icon_512x512"),(1024,"icon_512x512@2x")] {
    let image = NSImage(size:NSSize(width:size,height:size))
    image.lockFocus()
    let scale = CGFloat(size)/1024
    let transform = NSAffineTransform();transform.scale(by:scale);transform.concat()
    let background = NSBezierPath(roundedRect:NSRect(x:24,y:24,width:976,height:976),xRadius:218,yRadius:218)
    NSGradient(starting:NSColor(srgbRed:0.24,green:0.54,blue:0.44,alpha:1),ending:NSColor(srgbRed:0.10,green:0.31,blue:0.26,alpha:1))!.draw(in:background,angle:-45)
    let shadow = NSShadow();shadow.shadowColor = NSColor.black.withAlphaComponent(0.16);shadow.shadowBlurRadius = 28;shadow.shadowOffset = NSSize(width:0,height:-15);shadow.set()
    NSColor(srgbRed:0.96,green:0.97,blue:0.89,alpha:1).setFill()
    let paper = NSBezierPath();paper.move(to:NSPoint(x:312,y:200));paper.line(to:NSPoint(x:712,y:200));paper.curve(to:NSPoint(x:752,y:240),controlPoint1:NSPoint(x:742,y:200),controlPoint2:NSPoint(x:752,y:212));paper.line(to:NSPoint(x:752,y:655));paper.line(to:NSPoint(x:595,y:814));paper.line(to:NSPoint(x:312,y:814));paper.curve(to:NSPoint(x:272,y:774),controlPoint1:NSPoint(x:282,y:814),controlPoint2:NSPoint(x:272,y:802));paper.line(to:NSPoint(x:272,y:240));paper.curve(to:NSPoint(x:312,y:200),controlPoint1:NSPoint(x:272,y:212),controlPoint2:NSPoint(x:282,y:200));paper.close();paper.fill()
    NSShadow().set()
    NSColor(srgbRed:0.74,green:0.82,blue:0.68,alpha:1).setFill();let fold = NSBezierPath();fold.move(to:NSPoint(x:595,y:814));fold.line(to:NSPoint(x:595,y:695));fold.curve(to:NSPoint(x:635,y:655),controlPoint1:NSPoint(x:595,y:665),controlPoint2:NSPoint(x:609,y:655));fold.line(to:NSPoint(x:752,y:655));fold.close();fold.fill()
    let attributes:[NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:272,weight:.bold),.foregroundColor:NSColor(srgbRed:0.15,green:0.43,blue:0.35,alpha:1)]
    ("hi" as NSString).draw(at:NSPoint(x:365,y:304),withAttributes:attributes)
    image.unlockFocus()
    let rep = NSBitmapImageRep(data:image.tiffRepresentation!)!
    try rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(name+".png"))
}
