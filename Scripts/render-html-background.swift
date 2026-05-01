#!/usr/bin/env swift
// render-html-background.swift — Render background.html to a PNG via offscreen WebKit.
//
// Usage:
//   swift Scripts/render-html-background.swift <input.html> <output.png>
//
// The HTML must be sized to exactly 1320 × 800 px (2× retina canvas for a 660 × 400 DMG window).
// The output PNG is saved at that resolution with 144 DPI metadata so macOS treats it as @2x.

import Foundation
import WebKit
import AppKit

// MARK: - Args

let cliArgs = CommandLine.arguments
guard cliArgs.count >= 3 else {
    fputs("Usage: render-html-background.swift <input.html> <output.png>\n", stderr)
    exit(1)
}
let htmlPath = cliArgs[1]
let pngPath  = cliArgs[2]

// Render at the exact DMG window dimensions (1× logical points).
// Finder maps background-PNG pixels to logical points 1:1 at 72 DPI —
// no DPI tricks required; the PNG size must equal the window size exactly.
let viewportW: CGFloat = 960
let viewportH: CGFloat = 680

// MARK: - Renderer

class Renderer: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let outputPath: String
    var done = false

    init(htmlPath: String, outputPath: String) {
        self.outputPath = outputPath

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = false

        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences = prefs

        let frame = NSRect(x: 0, y: 0, width: viewportW, height: viewportH)
        webView = WKWebView(frame: frame, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")   // transparent chrome

        super.init()
        webView.navigationDelegate = self

        let url = URL(fileURLWithPath: htmlPath).standardizedFileURL
        let dir = url.deletingLastPathComponent()
        webView.loadFileURL(url, allowingReadAccessTo: dir)
    }

    // Called when the page finishes loading
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Wait for fonts + CSS animations to settle, then snapshot
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.takeSnapshot()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fputs("ERROR: navigation failed — \(error.localizedDescription)\n", stderr)
        NSApp.terminate(nil)
    }

    func takeSnapshot() {
        let cfg = WKSnapshotConfiguration()
        cfg.rect = NSRect(x: 0, y: 0, width: viewportW, height: viewportH)

        webView.takeSnapshot(with: cfg) { [weak self] image, error in
            guard let self = self else { return }

            if let error = error {
                fputs("ERROR: snapshot failed — \(error.localizedDescription)\n", stderr)
                NSApp.terminate(nil)
                return
            }
            guard let image = image else {
                fputs("ERROR: snapshot returned nil image\n", stderr)
                NSApp.terminate(nil)
                return
            }

            self.save(image: image)
        }
    }

    func save(image: NSImage) {
        // Get a CGImage from the snapshot
        var rect = NSRect(x: 0, y: 0, width: viewportW, height: viewportH)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            fputs("ERROR: cannot get CGImage from snapshot\n", stderr)
            NSApp.terminate(nil)
            return
        }

        let url = URL(fileURLWithPath: outputPath)
        guard let dest = CGImageDestinationCreateWithURL(
                url as CFURL, "public.png" as CFString, 1, nil)
        else {
            fputs("ERROR: cannot create PNG destination at \(outputPath)\n", stderr)
            NSApp.terminate(nil)
            return
        }

        // 144 DPI — WebKit on a retina display takes a 2× snapshot, so a 960×680
        // viewport produces a 1920×1360 PNG. Tagging it 144 DPI tells Finder this is
        // a @2× retina image of a 960×680 logical canvas, which matches the DMG window.
        // Without this tag Finder treats the 1920×1360 pixels as logical points and
        // only the top-left 960×680 quarter is visible.
        let props: [CFString: Any] = [
            kCGImagePropertyDPIWidth:  144,
            kCGImagePropertyDPIHeight: 144,
        ]
        CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)

        guard CGImageDestinationFinalize(dest) else {
            fputs("ERROR: CGImageDestinationFinalize failed\n", stderr)
            NSApp.terminate(nil)
            return
        }

        // Report the actual file dimensions, not the viewport size
        let pixelW = cgImage.width, pixelH = cgImage.height
        print("Written \(pixelW)×\(pixelH) px @ 144 DPI (\(Int(viewportW))×\(Int(viewportH)) logical) → \(outputPath)")
        NSApp.terminate(nil)
    }
}

// MARK: - App delegate (needed for WKWebView run loop)

class AppDelegate: NSObject, NSApplicationDelegate {
    var renderer: Renderer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        renderer = Renderer(htmlPath: htmlPath, outputPath: pngPath)
    }
}

// MARK: - Run

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
