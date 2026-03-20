import Cocoa
import QuartzCore

func processFinalIcon() {
    let userImagePath = CommandLine.arguments.count > 1
        ? CommandLine.arguments[1]
        : "icon_source.png"
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let assetURL = rootURL.appendingPathComponent("OpenEmu/Graphics.xcassets/OpenEmu.appiconset")
    let iconsetURL = rootURL.appendingPathComponent("OpenEmu/OpenEmu.iconset")
    
    print("Deploying Final Liquid Glass Icon...")

    guard let sourceImage = NSImage(contentsOfFile: userImagePath),
          let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("Error: Could not load user image.")
        return
    }

    try? FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: assetURL, withIntermediateDirectories: true)

    let sizes: [CGFloat] = [16, 32, 64, 128, 256, 512, 1024]
    var imagesJson: [[String: Any]] = []

    for size in sizes {
        autoreleasepool {
            let resultImage = NSImage(size: NSSize(width: size, height: size))
            resultImage.lockFocus()
            let context = NSGraphicsContext.current!.cgContext
            
            // Draw the full image exactly as provided
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

            resultImage.unlockFocus()
            
            let tiffData = resultImage.tiffRepresentation!
            let bitmap = NSBitmapImageRep(data: tiffData)!
            let pngData = bitmap.representation(using: .png, properties: [:])!
            
            let srgbFilename = "icon-\(Int(size))-srgb.png"
            let p3Filename = "icon-\(Int(size))-p3.png"
            try? pngData.write(to: assetURL.appendingPathComponent(srgbFilename))
            try? pngData.write(to: assetURL.appendingPathComponent(p3Filename))

            let nameMap: [CGFloat: String] = [
                16: "icon_16x16.png", 32: "icon_16x16@2x.png", 64: "icon_32x32@2x.png",
                128: "icon_128x128.png", 256: "icon_128x128@2x.png", 512: "icon_512x512.png", 1024: "icon_512x512@2x.png"
            ]
            if let iconsetName = nameMap[size] {
                try! pngData.write(to: iconsetURL.appendingPathComponent(iconsetName))
            }
            
            let sizesMap: [CGFloat: (String, String)] = [
                16: ("16x16", "1x"), 32: ("16x16", "2x"), 64: ("32x32", "2x"),
                128: ("128x128", "1x"), 256: ("128x128", "2x"), 512: ("512x512", "1x"),
                1024: ("512x512", "2x")
            ]
            if let (sizeStr, scale) = sizesMap[size] {
                imagesJson.append(["idiom": "mac", "size": sizeStr, "scale": scale, "filename": srgbFilename, "display-gamut": "sRGB"])
                imagesJson.append(["idiom": "mac", "size": sizeStr, "scale": scale, "filename": p3Filename, "display-gamut": "display-P3"])
            }
        }
    }
    
    let contents: [String: Any] = ["images": imagesJson, "info": ["author": "xcode", "version": 1]]
    let data = try! JSONSerialization.data(withJSONObject: contents, options: .prettyPrinted)
    try! data.write(to: assetURL.appendingPathComponent("Contents.json"))
    
    print("Final icon deployed successfully.")
}

processFinalIcon()
