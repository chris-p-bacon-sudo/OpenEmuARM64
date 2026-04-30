#!/usr/bin/env swift
// generate-dmg-bg.swift — Generate the OpenEmu-Silicon DMG installer background PNG.
//
// Usage:
//   swift Scripts/generate-dmg-bg.swift <output.png> [assets-dir]
//
// assets-dir defaults to Scripts/dmg-assets/ relative to the repo root.
// Requires: Scripts/dmg-assets/retro-grid.jpg and openemu-logo.png

import Foundation
import CoreGraphics
import AppKit

// MARK: - Args

let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "dmg-background.png"

// Resolve asset dir: default to sibling of this script
let scriptDir = (args[0] as NSString).deletingLastPathComponent
let defaultAssetDir = (scriptDir as NSString).appendingPathComponent("dmg-assets")
let assetDir = args.count > 2 ? args[2] : defaultAssetDir

func assetURL(_ name: String) -> URL {
    URL(fileURLWithPath: (assetDir as NSString).appendingPathComponent(name))
}

// MARK: - Helpers

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
}
func hex(_ v: UInt32, a: CGFloat = 1) -> CGColor {
    rgba(CGFloat((v >> 16) & 0xFF), CGFloat((v >> 8) & 0xFF), CGFloat(v & 0xFF), a)
}

// SRGB approximations of the HTML design tokens
let bgColor   = hex(0x07060D)          // #07060d
let magenta   = hex(0xCC2040)          // ~oklch(0.55 0.22 25)
let blue      = hex(0x2240CC)          // ~oklch(0.45 0.22 265)
let cyan      = hex(0x7FEEDD)          // ~oklch(0.86 0.15 200)
let cyanDeep  = hex(0x44C4AA)          // ~oklch(0.72 0.15 205)
let inkColor  = hex(0xE9E7FF)
let inkDim    = hex(0x8E88B8)

// MARK: - Canvas

let W = 660
let H = 420       // includes a little extra for the content area below the Finder titlebar
let S = 2         // render @2x, save as @2x PNG

let cW = CGFloat(W)
let cH = CGFloat(H)

guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(
        data: nil,
        width: W * S, height: H * S,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
else { fputs("ERROR: cannot create CGContext\n", stderr); exit(1) }

ctx.scaleBy(x: CGFloat(S), y: CGFloat(S))
ctx.translateBy(x: 0, y: cH)   // flip to top-left origin
ctx.scaleBy(x: 1, y: -1)

// MARK: - CoreText draw helpers

func ctLine(_ str: String, fontName: String, size: CGFloat,
            color: CGColor, kern: CGFloat = 0) -> CTLine {
    let font = CTFontCreateWithName(fontName as CFString, size, nil)
    let attrs: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: color,
        kCTKernAttributeName: kern as CFNumber,
    ]
    let as_ = CFAttributedStringCreate(nil, str as CFString, attrs as CFDictionary)!
    return CTLineCreateWithAttributedString(as_)
}

func lineWidth(_ line: CTLine) -> CGFloat {
    CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
}

// Draw a CTLine centred at (x, topY) — topY is the TOP of the text in our flipped coords.
func drawCentered(_ line: CTLine, x: CGFloat, topY: CGFloat) {
    let w = lineWidth(line)
    draw(line, leftX: x - w / 2, topY: topY)
}

// Draw a CTLine with its left edge at leftX.
func draw(_ line: CTLine, leftX: CGFloat, topY: CGFloat) {
    var asc: CGFloat = 0
    CTLineGetTypographicBounds(line, &asc, nil, nil)
    ctx.saveGState()
    // Unflip so CoreText can draw right-side up; baseline sits at topY + asc
    ctx.translateBy(x: leftX, y: topY + asc)
    ctx.scaleBy(x: 1, y: -1)
    ctx.textMatrix = .identity
    ctx.textPosition = .zero
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

func drawRight(_ line: CTLine, rightX: CGFloat, topY: CGFloat) {
    draw(line, leftX: rightX - lineWidth(line), topY: topY)
}

// MARK: - Gradient helper

func radialGradient(center: CGPoint, radius: CGFloat,
                    inner: CGColor, outer: CGColor) {
    let locs: [CGFloat] = [0, 1]
    guard let g = CGGradient(colorsSpace: cs, colors: [inner, outer] as CFArray,
                              locations: locs) else { return }
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: radius, options: [])
}

func linearGradient(from p0: CGPoint, to p1: CGPoint,
                    colors: [CGColor], locations: [CGFloat]) {
    guard let g = CGGradient(colorsSpace: cs, colors: colors as CFArray,
                              locations: locations) else { return }
    ctx.drawLinearGradient(g, start: p0, end: p1, options: [])
}

// MARK: - Load image helper

func loadImage(_ url: URL) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          CGImageSourceGetCount(src) > 0
    else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

// MARK: - ① Base: retro-grid.jpg, scaled to fill

ctx.setFillColor(bgColor)
ctx.fill(CGRect(x: 0, y: 0, width: cW, height: cH))

if let grid = loadImage(assetURL("retro-grid.jpg")) {
    let gW = CGFloat(grid.width)
    let gH = CGFloat(grid.height)
    // Scale to fill height, then center-crop width
    let scale = cH / gH
    let scaledW = gW * scale
    let offsetX = (scaledW - cW) / 2
    ctx.draw(grid, in: CGRect(x: -offsetX, y: 0, width: scaledW, height: cH))
}

// MARK: - ② Gradient overlays

// Dark overlay matching HTML: linear(180deg, rgba(7,6,13,0.45) → rgba(7,6,13,0.85))
linearGradient(
    from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: cH),
    colors: [bgColor.copy(alpha: 0.45)!, bgColor.copy(alpha: 0.88)!],
    locations: [0, 1]
)

// Magenta glow — upper centre
radialGradient(
    center: CGPoint(x: cW / 2, y: 0),
    radius: cW * 0.42,
    inner: magenta.copy(alpha: 0.50)!,
    outer: magenta.copy(alpha: 0)!
)

// Blue glow — lower centre
radialGradient(
    center: CGPoint(x: cW / 2, y: cH),
    radius: cW * 0.40,
    inner: blue.copy(alpha: 0.40)!,
    outer: blue.copy(alpha: 0)!
)

// MARK: - ③ Scanlines

ctx.saveGState()
var sy: CGFloat = 0.5
while sy < cH {
    ctx.setFillColor(gray: 0, alpha: 0.22)
    ctx.fill(CGRect(x: 0, y: sy, width: cW, height: 1))
    sy += 3
}
ctx.restoreGState()

// MARK: - ④ OpenEmu logo (top-centre)

let logoY: CGFloat = 20
let logoHeight: CGFloat = 52

if let logo = loadImage(assetURL("openemu-logo.png")) {
    let lW = CGFloat(logo.width)
    let lH = CGFloat(logo.height)
    let scale = logoHeight / lH
    let scaledLogoW = lW * scale
    let logoX = (cW - scaledLogoW) / 2

    // Drop shadow / glow
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 18,
                  color: magenta.copy(alpha: 0.75))
    ctx.draw(logo, in: CGRect(x: logoX, y: logoY,
                               width: scaledLogoW, height: logoHeight))
    ctx.restoreGState()

    // Crisp second pass on top
    ctx.draw(logo, in: CGRect(x: logoX, y: logoY,
                               width: scaledLogoW, height: logoHeight))
}

// Version badge
let badgeLine = ctLine("NATIVE APPLE SILICON  ·  OPEN SOURCE",
                         fontName: "Menlo", size: 9, color: cyanDeep, kern: 1)
drawCentered(badgeLine, x: cW / 2, topY: logoY + logoHeight + 8)

// MARK: - ⑤ Headline

let h1TopY: CGFloat = 108

// Line 1: "DRAG OPENEMU INTO"
let h1a = ctLine("DRAG OPENEMU INTO",
                   fontName: "Menlo-Bold", size: 16, color: inkColor, kern: 2)
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 14, color: magenta.copy(alpha: 0.85))
drawCentered(h1a, x: cW / 2, topY: h1TopY)
ctx.restoreGState()
drawCentered(h1a, x: cW / 2, topY: h1TopY)

// Line 2: "APPLICATIONS" in cyan
let h1b = ctLine("APPLICATIONS",
                   fontName: "Menlo-Bold", size: 16, color: cyan, kern: 2)
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 14, color: cyanDeep.copy(alpha: 0.85))
drawCentered(h1b, x: cW / 2, topY: h1TopY + 24)
ctx.restoreGState()
drawCentered(h1b, x: cW / 2, topY: h1TopY + 24)

// Sub-headline
let subLine = ctLine("Ready Player One",
                      fontName: "Menlo", size: 12, color: inkDim, kern: 1)
drawCentered(subLine, x: cW / 2, topY: h1TopY + 52)

// MARK: - ⑥ Icon-area glows (pedestal effect under where each icon sits)

let iconCY: CGFloat = 240   // vertical centre of icons in content area

// Left pedestal glow (magenta-tinted)
radialGradient(
    center: CGPoint(x: 175, y: iconCY + 68),
    radius: 90,
    inner: magenta.copy(alpha: 0.40)!,
    outer: magenta.copy(alpha: 0)!
)

// Right pedestal glow (blue-tinted)
radialGradient(
    center: CGPoint(x: 485, y: iconCY + 68),
    radius: 90,
    inner: blue.copy(alpha: 0.40)!,
    outer: blue.copy(alpha: 0)!
)

// MARK: - ⑦ Arrow (left → right between icon positions)

let arrowY: CGFloat = iconCY - 12
let arrowX1: CGFloat = 255    // right edge of left icon area
let arrowX2: CGFloat = 405    // left edge of right icon area
let headLen: CGFloat = 18
let headHalf: CGFloat = 9

// Glow pass — wide, soft
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 12, color: cyan.copy(alpha: 0.80))
ctx.setStrokeColor(cyan.copy(alpha: 0.55)!)
ctx.setLineWidth(4)
ctx.move(to: CGPoint(x: arrowX1, y: arrowY))
ctx.addLine(to: CGPoint(x: arrowX2, y: arrowY))
ctx.strokePath()
ctx.restoreGState()

// Crisp shaft
ctx.setStrokeColor(cyan)
ctx.setLineWidth(3)
ctx.move(to: CGPoint(x: arrowX1, y: arrowY))
ctx.addLine(to: CGPoint(x: arrowX2 - headLen + 2, y: arrowY))
ctx.strokePath()

// Arrowhead
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 8, color: cyan.copy(alpha: 0.80))
ctx.setFillColor(cyan)
ctx.beginPath()
ctx.move(to: CGPoint(x: arrowX2, y: arrowY))
ctx.addLine(to: CGPoint(x: arrowX2 - headLen, y: arrowY - headHalf))
ctx.addLine(to: CGPoint(x: arrowX2 - headLen, y: arrowY + headHalf))
ctx.closePath()
ctx.fillPath()
ctx.restoreGState()

// MARK: - ⑧ Icon-area labels ("DRAG ME" / "DROP HERE")

let labelTopY = iconCY + 80   // below icon bottom (~128px icon → icon top≈176, bottom≈304)

// These appear below where Finder will draw the filename label
let dragMe  = ctLine("DRAG ME",   fontName: "Menlo", size: 10, color: inkDim, kern: 2)
let dropHere = ctLine("DROP HERE", fontName: "Menlo", size: 10, color: inkDim, kern: 2)
drawCentered(dragMe,   x: 175, topY: labelTopY)
drawCentered(dropHere, x: 485, topY: labelTopY)

// MARK: - ⑨ Corner marks

let cmFont  = "Menlo-Bold"
let cmSize: CGFloat  = 8
let cmColor = inkDim.copy(alpha: 0.55)!
let cmKern: CGFloat  = 1.5
let cmPadX: CGFloat  = 14
let cmTopY: CGFloat  = 8
let cmBotY  = cH - 18

draw(ctLine("SYS // DMG-01",   fontName: cmFont, size: cmSize, color: cmColor, kern: cmKern),
     leftX: cmPadX, topY: cmTopY)
drawRight(ctLine("PLAYER 1",   fontName: cmFont, size: cmSize, color: cmColor, kern: cmKern),
          rightX: cW - cmPadX, topY: cmTopY)
draw(ctLine("© 2026  OPENEMU", fontName: cmFont, size: cmSize, color: cmColor, kern: cmKern),
     leftX: cmPadX, topY: cmBotY)
drawRight(ctLine("READY",      fontName: cmFont, size: cmSize, color: cmColor, kern: cmKern),
          rightX: cW - cmPadX, topY: cmBotY)

// MARK: - ⑩ Bottom instruction text

let instr = ctLine(
    "HOLD CLICK  ·  DRAG RIGHT  ·  RELEASE OVER APPLICATIONS",
    fontName: "Menlo", size: 9, color: inkDim.copy(alpha: 0.80)!, kern: 0.8
)
drawCentered(instr, x: cW / 2, topY: cH - 35)

// MARK: - Export

guard let image = ctx.makeImage() else {
    fputs("ERROR: cannot create CGImage\n", stderr); exit(1)
}

let outURL = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, "public.png" as CFString, 1, nil)
else { fputs("ERROR: cannot create image destination at \(outPath)\n", stderr); exit(1) }

// Write as @2x — DPI metadata so Finder treats it as retina
let props: [CFString: Any] = [
    kCGImagePropertyDPIWidth:  144,
    kCGImagePropertyDPIHeight: 144,
]
CGImageDestinationAddImage(dest, image, props as CFDictionary)
guard CGImageDestinationFinalize(dest)
else { fputs("ERROR: cannot write PNG\n", stderr); exit(1) }

print("Written \(W)×\(H) @2x → \(outPath)")
