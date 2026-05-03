import Cocoa

func generateIconSet() {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let assetURL = rootURL.appendingPathComponent("OpenEmu/Graphics.xcassets/OpenEmu.appiconset")
    let iconsetURL = rootURL.appendingPathComponent("OpenEmu/OpenEmu.iconset")
    
    print("Generating Professional 3D Grape Purple Icon set...")

    try? FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: assetURL, withIntermediateDirectories: true)

    let sizes: [CGFloat] = [16, 32, 64, 128, 256, 512, 1024]
    var imagesJson: [[String: Any]] = []

    for size in sizes {
        autoreleasepool {
            let image = NSImage(size: NSSize(width: size, height: size))
            image.lockFocus()
            let context = NSGraphicsContext.current!.cgContext
            drawPremium3DGrapePurpleN64(in: context, size: size)
            image.unlockFocus()
            
            let tiffData = image.tiffRepresentation!
            let bitmap = NSBitmapImageRep(data: tiffData)!
            let pngData = bitmap.representation(using: .png, properties: [:])!
            
            let srgbFilename = "icon-\(Int(size))-srgb.png"
            let p3Filename = "icon-\(Int(size))-p3.png"
            
            try? pngData.write(to: assetURL.appendingPathComponent(srgbFilename))
            try? pngData.write(to: assetURL.appendingPathComponent(p3Filename))

            let sizesMap: [CGFloat: (String, String)] = [
                16: ("16x16", "1x"), 32: ("16x16", "2x"), 64: ("32x32", "2x"),
                128: ("128x128", "1x"), 256: ("128x128", "2x"), 512: ("512x512", "1x"),
                1024: ("512x512", "2x")
            ]
            if let (sizeStr, scale) = sizesMap[size] {
                imagesJson.append(["idiom": "mac", "size": sizeStr, "scale": scale, "filename": srgbFilename, "display-gamut": "sRGB"])
                imagesJson.append(["idiom": "mac", "size": sizeStr, "scale": scale, "filename": p3Filename, "display-gamut": "display-P3"])
            }
            if size == 32 { imagesJson.append(["idiom": "mac", "size": "32x32", "scale": "1x", "filename": srgbFilename]) }
            if size == 256 { imagesJson.append(["idiom": "mac", "size": "256x256", "scale": "1x", "filename": srgbFilename]) }

            let nameMap: [CGFloat: String] = [
                16: "icon_16x16.png", 32: "icon_16x16@2x.png", 64: "icon_32x32@2x.png",
                128: "icon_128x128.png", 256: "icon_128x128@2x.png", 512: "icon_512x512.png", 1024: "icon_512x512@2x.png"
            ]
            if let iconsetName = nameMap[size] {
                try! pngData.write(to: iconsetURL.appendingPathComponent(iconsetName))
            }
        }
    }
    
    let contents: [String: Any] = ["images": imagesJson, "info": ["author": "xcode", "version": 1]]
    let data = try! JSONSerialization.data(withJSONObject: contents, options: .prettyPrinted)
    try! data.write(to: assetURL.appendingPathComponent("Contents.json"))
}

func drawPremium3DGrapePurpleN64(in context: CGContext, size: CGFloat) {
    let s = size / 1024.0
    
    // 1. Stage Background (Modern Apple-style gradient)
    context.saveGState()
    context.addEllipse(in: CGRect(x: 20*s, y: 20*s, width: 984*s, height: 984*s))
    context.clip()
    let bgColors = [NSColor(white: 0.1, alpha: 1.0).cgColor, NSColor(white: 0.2, alpha: 1.0).cgColor]
    let bgGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors as CFArray, locations: [0, 1])!
    context.drawLinearGradient(bgGrad, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
    context.restoreGState()

    // 2. 3D Perspective Matrix Simulation
    // We rotate around Y and tilt around X
    func project(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGPoint {
        let angleY: CGFloat = 0.5  // 3/4 turn
        let angleX: CGFloat = -0.3 // tilt back
        
        // Rotation Y
        let x1 = x * cos(angleY) + z * sin(angleY)
        let z1 = z * cos(angleY) - x * sin(angleY)
        
        // Rotation X
        let y2 = y * cos(angleX) - z1 * sin(angleX)
        let z2 = z1 * cos(angleX) + y * sin(angleX)
        
        // Perspective projection
        let d: CGFloat = 1200
        let scale = d / (d - z2)
        return CGPoint(x: 512*s + x1 * scale * s, y: 450*s + y2 * scale * s)
    }

    // 3. Funtastic Grape Colors
    let grapeColor = NSColor(red: 0.35, green: 0.1, blue: 0.55, alpha: 0.85).cgColor
    let grapeHighlight = NSColor(red: 0.5, green: 0.2, blue: 0.7, alpha: 0.9).cgColor
    let grapeShadow = NSColor(red: 0.15, green: 0.05, blue: 0.25, alpha: 0.95).cgColor

    // 4. Draw Depth Shell (Iterative slicing for 3D volume)
    for z in (0..<30).reversed() {
        let zOff = CGFloat(z) * 2.0
        let alpha = z == 0 ? 1.0 : 0.6
        let color = z == 0 ? grapeColor : grapeShadow
        
        context.saveGState()
        context.beginPath()
        
        // Main Body Loop
        let bodyPoints = [
            project(-380, 0, zOff), project(380, 0, zOff),
            project(380, 300, zOff), project(-380, 300, zOff)
        ]
        context.addLines(between: bodyPoints)
        context.closePath()
        
        // Handles
        func handle(_ x: CGFloat, _ yEnd: CGFloat) {
            let pts = [project(x-70, 50, zOff), project(x+70, 50, zOff), project(x+70, yEnd, zOff), project(x-70, yEnd, zOff)]
            context.addLines(between: pts)
            context.closePath()
        }
        handle(-260, -350) // Left
        handle(0, -400)    // Center
        handle(260, -350)  // Right
        
        context.setFillColor(color)
        if z == 0 {
            context.setShadow(offset: CGSize(width: 0, height: -30*s), blur: 60*s, color: NSColor.black.withAlphaComponent(0.6).cgColor)
        }
        context.fillPath()
        context.restoreGState()
    }

    // 5. Internal PCB Simulation (Deep glow)
    context.saveGState()
    let pcbRect = [project(-100, 50, 10), project(100, 50, 10), project(100, 200, 10), project(-100, 200, 10)]
    context.addLines(between: pcbRect)
    context.clip()
    let pcbGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor(red: 0, green: 0.2, blue: 0.1, alpha: 0.4).cgColor, NSColor.clear.cgColor] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(pcbGrad, startCenter: project(0, 125, 10), startRadius: 0, endCenter: project(0, 125, 10), endRadius: 150*s, options: [])
    context.restoreGState()

    // 6. 3D Surface Lighting (Specular Gloss)
    context.saveGState()
    context.setBlendMode(.screen)
    let glossPath = CGMutablePath()
    glossPath.addEllipse(in: CGRect(x: 300*s, y: 550*s, width: 400*s, height: 200*s))
    context.addPath(glossPath)
    context.setFillColor(NSColor(white: 1.0, alpha: 0.15).cgColor)
    context.fillPath()
    context.restoreGState()

    // 7. PRECISION BUTTON PLACEMENT (Based on 3D Projection)
    func drawButton(at: CGPoint, color: NSColor, r: CGFloat) {
        let p = project(at.x, at.y, 35)
        let rect = CGRect(x: p.x - r*s, y: p.y - r*s, width: r*2*s, height: r*2*s)
        
        context.saveGState()
        // Depth
        context.addEllipse(in: rect.offsetBy(dx: 2*s, dy: -4*s))
        context.setFillColor(color.shadow(withLevel: 0.4)!.cgColor)
        context.fillPath()
        // Face
        context.addEllipse(in: rect)
        context.setFillColor(color.cgColor)
        context.fillPath()
        // Shine
        let shine = rect.insetBy(dx: r*0.5*s, dy: r*0.5*s).offsetBy(dx: 0, dy: r*0.2*s)
        context.addEllipse(in: shine)
        context.setFillColor(NSColor.white.withAlphaComponent(0.3).cgColor)
        context.fillPath()
        context.restoreGState()
    }

    // D-Pad (Left handle)
    drawButton(at: CGPoint(x: -260, y: 180), color: .darkGray, r: 45)
    
    // Joystick (Center handle)
    drawButton(at: CGPoint(x: 0, y: 100), color: .gray, r: 60)
    
    // A/B (Right handle)
    drawButton(at: CGPoint(x: 230, y: 150), color: .systemBlue, r: 40)
    drawButton(at: CGPoint(x: 300, y: 220), color: .systemGreen, r: 40)
    
    // C-Buttons (Right handle, Yellow)
    let cy = NSColor.systemYellow
    drawButton(at: CGPoint(x: 230, y: 300), color: cy, r: 25) // C-Down
    drawButton(at: CGPoint(x: 230, y: 400), color: cy, r: 25) // C-Up
    drawButton(at: CGPoint(x: 180, y: 350), color: cy, r: 25) // C-Left
    drawButton(at: CGPoint(x: 280, y: 350), color: cy, r: 25) // C-Right

    // Start (Center)
    drawButton(at: CGPoint(x: 0, y: 280), color: .systemRed, r: 25)
    
    // 8. Final Logo Simulation (Nintendo logo area)
    let logoP = project(0, 420, 35)
    let logoRect = CGRect(x: logoP.x-100*s, y: logoP.y-25*s, width: 200*s, height: 50*s)
    let logoPath = CGPath(roundedRect: logoRect, cornerWidth: 10*s, cornerHeight: 10*s, transform: nil)
    context.addPath(logoPath)
    context.setFillColor(NSColor(white: 0, alpha: 0.2).cgColor)
    context.fillPath()
}

generateIconSet()
