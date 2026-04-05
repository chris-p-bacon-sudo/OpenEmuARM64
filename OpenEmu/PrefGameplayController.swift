// Copyright (c) 2020, OpenEmu Team
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in the
//       documentation and/or other materials provided with the distribution.
//     * Neither the name of the OpenEmu Team nor the
//       names of its contributors may be used to endorse or promote products
//       derived from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
// DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import Cocoa
import OpenEmuKit

final class PrefGameplayController: NSViewController {
    
    @IBOutlet var globalDefaultShaderSelection: NSPopUpButton!
    
    private var token: NSObjectProtocol?
    
    // Injected slider controls (nil until viewDidAppear)
    private var saturationSlider: NSSlider?
    private var saturationLabel:  NSTextField?
    private var gammaSlider:      NSSlider?
    private var gammaLabel:       NSTextField?

    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        loadShaderMenu()
        
        token = NotificationCenter.default.addObserver(forName: .shaderModelCustomShadersDidChange, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            
            self.loadShaderMenu()
        }
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        guard saturationSlider == nil else { return }
        addSliders()
    }
    
    deinit {
        if let token = token {
            NotificationCenter.default.removeObserver(token)
            self.token = nil
        }
    }
    
    // MARK: - Slider injection

    private func addSliders() {
        let sat = OEGameDocument.clampedSaturation((UserDefaults.standard.object(forKey: OEGameSaturationKey) as? Float) ?? 1.0)
        let gam = OEGameDocument.clampedGamma((UserDefaults.standard.object(forKey: OEGameGammaKey) as? Float) ?? 1.0)

        let rowH:   CGFloat = 24
        let gap:    CGFloat = 12
        let extraH: CGFloat = gap + rowH + gap + rowH + gap
        let extraW: CGFloat = 140

        // ── Grow the view ─────────────────────────────────────────────────
        view.setFrameSize(NSSize(width: view.frame.width + extraW,
                                 height: view.frame.height + extraH))

        for sv in view.subviews {
            sv.setFrameOrigin(NSPoint(x: sv.frame.origin.x,
                                      y: sv.frame.origin.y + extraH))
        }

        // ── Grow the window to match ───────────────────────────────────────
        if let window = view.window {
            var wf = window.frame
            wf.origin.y    -= extraH
            wf.size.height += extraH
            wf.size.width  += extraW
            window.setFrame(wf, display: true, animate: false)
        }

        let shaderX = globalDefaultShaderSelection.frame.minX
        let rowW    = view.frame.width - shaderX - 20

        let gamY = gap
        let satY = gap + rowH + gap

        let (satView, satSlider, satLbl) = makeRow(
            label: "Saturation:", value: sat, minValue: 0.5, maxValue: 3.0,
            frame: NSRect(x: shaderX, y: satY, width: rowW, height: rowH),
            action: #selector(saturationChanged(_:))
        )
        let (gamView, gamSlider, gamLbl) = makeRow(
            label: "Gamma:", value: gam, minValue: 0.5, maxValue: 2.0,
            frame: NSRect(x: shaderX, y: gamY, width: rowW, height: rowH),
            action: #selector(gammaChanged(_:))
        )

        view.addSubview(satView)
        view.addSubview(gamView)

        saturationSlider = satSlider
        saturationLabel  = satLbl
        gammaSlider      = gamSlider
        gammaLabel       = gamLbl
    }

    private func makeRow(
        label: String, value: Float,
        minValue: Double, maxValue: Double,
        frame: NSRect, action: Selector
    ) -> (NSView, NSSlider, NSTextField) {

        let container = NSView(frame: frame)

        let labelW: CGFloat = 80
        let pctW:   CGFloat = 44
        let sliderW = frame.width - labelW - pctW - 8

        let lbl = NSTextField(labelWithString: label)
        lbl.font  = .systemFont(ofSize: NSFont.systemFontSize)
        lbl.frame = NSRect(x: 0, y: 0, width: labelW, height: frame.height)
        container.addSubview(lbl)

        let slider = NSSlider(value: Double(value), minValue: minValue, maxValue: maxValue,
                              target: self, action: action)
        slider.isContinuous = true
        slider.frame = NSRect(x: labelW + 4, y: 0, width: sliderW, height: frame.height)
        container.addSubview(slider)

        let pct = NSTextField(
            labelWithString: String(format: "%.0f%%", value * 100))
        pct.font  = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 1,
                                               weight: .regular)
        pct.frame = NSRect(x: labelW + 4 + sliderW + 4, y: 0,
                           width: pctW, height: frame.height)
        container.addSubview(pct)

        return (container, slider, pct)
    }

    // MARK: - Slider actions

    @objc private func saturationChanged(_ sender: NSSlider) {
        let v = OEGameDocument.clampedSaturation(sender.floatValue)
        saturationLabel?.stringValue = String(format: "%.0f%%", v * 100)
        UserDefaults.standard.set(v, forKey: OEGameSaturationKey)
        
        NSDocumentController.shared.documents.forEach {
            ($0 as? OEGameDocument)?.setSaturation(v, asDefault: false)
        }
    }

    @objc private func gammaChanged(_ sender: NSSlider) {
        let v = OEGameDocument.clampedGamma(sender.floatValue)
        gammaLabel?.stringValue = String(format: "%.0f%%", v * 100)
        UserDefaults.standard.set(v, forKey: OEGameGammaKey)
        
        NSDocumentController.shared.documents.forEach {
            ($0 as? OEGameDocument)?.setGamma(v, asDefault: false)
        }
    }
    
    private func loadShaderMenu() {
        
        let globalShaderMenu = NSMenu()
        
        let systemShaders = OEShaderStore.shared.sortedSystemShaderNames
        systemShaders.forEach { shaderName in
            globalShaderMenu.addItem(withTitle: shaderName, action: nil, keyEquivalent: "")
        }
        
        let customShaders = OEShaderStore.shared.sortedCustomShaderNames
        if !customShaders.isEmpty {
            globalShaderMenu.addItem(.separator())
            
            customShaders.forEach { shaderName in
                globalShaderMenu.addItem(withTitle: shaderName, action: nil, keyEquivalent: "")
            }
        }
        
        globalDefaultShaderSelection.menu = globalShaderMenu
        
        let selectedShaderName = OEShaderStore.shared.defaultShaderName
        
        if globalDefaultShaderSelection.item(withTitle: selectedShaderName) != nil {
            globalDefaultShaderSelection.selectItem(withTitle: selectedShaderName)
        } else {
            globalDefaultShaderSelection.selectItem(at: 0)
        }
    }
    
    @IBAction func changeGlobalDefaultShader(_ sender: Any?) {
        guard let context = OELibraryDatabase.default?.mainThreadContext else { return }
        
        guard let shaderName = globalDefaultShaderSelection.selectedItem?.title else { return }
        
        let allSystemIdentifiers = OEDBSystem.allSystemIdentifiers(in: context)
        allSystemIdentifiers.forEach(OESystemShaderStore.shared.resetShader(forSystem:))
        OEShaderStore.shared.defaultShaderName = shaderName
    }
}

// MARK: - PreferencePane

extension PrefGameplayController: PreferencePane {
    
    var icon: NSImage? { NSImage(named: "gameplay_tab_icon") }
    
    var panelTitle: String { "Gameplay" }
    
    var viewSize: NSSize { view.frame.size }
}
