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

let viewportW: CGFloat = 1320
let viewportH: CGFloat = 800

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
        guard let tiff = image.tiffRepresentation,
              let rep  = NSBitmapImageRep(data: tiff)
        else {
            fputs("ERROR: cannot create bitmap from snapshot\n", stderr)
            NSApp.terminate(nil)
            return
        }

        // Tag as 144 DPI so macOS treats the PNG as @2x retina
        rep.pixelsWide = Int(viewportW)
        rep.pixelsHigh = Int(viewportH)

        guard let png = rep.representation(using: .png, properties: [:]) else {
            fputs("ERROR: cannot encode PNG\n", stderr)
            NSApp.terminate(nil)
            return
        }

        do {
            try png.write(to: URL(fileURLWithPath: outputPath))
            print("Written \(Int(viewportW))×\(Int(viewportH)) @2x → \(outputPath)")
        } catch {
            fputs("ERROR: cannot write PNG — \(error.localizedDescription)\n", stderr)
        }

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
