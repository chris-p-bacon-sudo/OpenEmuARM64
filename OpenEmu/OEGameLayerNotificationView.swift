// Copyright (c) 2019, OpenEmu Team
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

// MARK: - Achievement Banner

final class OEAchievementBannerView: NSView {

    static let bannerWidth:  CGFloat = 310
    static let bannerHeight: CGFloat = 66

    private let headerLabel = NSTextField(labelWithString: "Achievement Unlocked!")
    private let titleLabel  = NSTextField(labelWithString: "")
    private let ptsLabel    = NSTextField(labelWithString: "")
    private let iconView    = NSImageView()

    private var hideWorkItem: DispatchWorkItem?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.88).cgColor
        alphaValue = 0

        let iconConfig = NSImage.SymbolConfiguration(pointSize: 26, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: "trophy.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(iconConfig)
        iconView.contentTintColor = .systemYellow
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        headerLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        headerLabel.textColor = .systemYellow
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerLabel)

        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        ptsLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        ptsLabel.textColor = NSColor(white: 0.75, alpha: 1)
        ptsLabel.alignment = .right
        ptsLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ptsLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 30),
            iconView.heightAnchor.constraint(equalToConstant: 30),

            ptsLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            ptsLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            ptsLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),

            headerLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            headerLabel.trailingAnchor.constraint(lessThanOrEqualTo: ptsLabel.leadingAnchor, constant: -8),
            headerLabel.topAnchor.constraint(equalTo: topAnchor, constant: 13),

            titleLabel.leadingAnchor.constraint(equalTo: headerLabel.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: ptsLabel.leadingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 3),
        ])
    }

    func show(title: String, points: UInt32) {
        titleLabel.stringValue = title
        ptsLabel.stringValue   = points > 0 ? "+\(points) pts" : ""

        hideWorkItem?.cancel()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }

        let item = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.5
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self?.animator().alphaValue = 0
            }
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5, execute: item)
    }
}

// MARK: - HUD Icon Notification

@IBDesignable
final class OEGameLayerNotificationView: NSImageView {
    
    static let OEShowNotificationsKey = "OEShowNotifications"
    
    public var disableNotifications: Bool = false
    
    lazy var quicksaveImage     = NSImage(named: "hud_quicksave_notification")
    lazy var screenshotImage    = NSImage(named: "hud_screenshot_notification")
    lazy var fastForwardImage   = NSImage(named: "hud_fastforward_notification")
    lazy var rewindImage        = NSImage(named: "hud_rewind_notification")
    lazy var stepForwardImage   = NSImage(named: "hud_stepforward_notification")
    lazy var stepBackwardImage  = NSImage(named: "hud_stepbackward_notification")
    
    var isFastForwarding: Bool  = false
    var isRewinding: Bool       = false
    
    override var wantsUpdateLayer: Bool { return true }
    
    var showNotifications: Bool {
        return UserDefaults.standard.bool(forKey: Self.OEShowNotificationsKey)
    }
    
    // MARK: - Initialization
    
    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.setup()
    }
    
    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setup()
    }
    
    private func setup() {
        self.wantsLayer = true
        self.layerContentsRedrawPolicy = .onSetNeedsDisplay
    }
    
    // MARK: - Notifications
    
    @objc public func showFastForward(enabled: Bool) {
        performNotification(img: fastForwardImage, enabled: enabled, state: &isFastForwarding)
        if enabled {
            postAccessibilityNotification(announcement: NSLocalizedString("Fast Forward", tableName: "ControlLabels", comment: ""))
        }
    }
    
    @objc public func showRewind(enabled: Bool) {
        performNotification(img: rewindImage, enabled: enabled, state: &isRewinding)
        if enabled {
            postAccessibilityNotification(announcement: NSLocalizedString("Rewind", tableName: "ControlLabels", comment: ""))
        }
    }
    
    @objc public func showQuickSave() {
        performShowHideNotification(img: quicksaveImage)
        postAccessibilityNotification(announcement: NSLocalizedString("Quick Save", tableName: "ControlLabels", comment: ""))
    }
    
    @objc public func showScreenShot() {
        performShowHideNotification(img: screenshotImage)
        postAccessibilityNotification(announcement: NSLocalizedString("Screenshot", tableName: "ControlLabels", comment: ""))
    }
    
    @objc public func showStepForward() {
        performShowHideNotification(img: stepForwardImage)
        postAccessibilityNotification(announcement: NSLocalizedString("Step Forward", tableName: "ControlLabels", comment: ""))
    }
    
    @objc public func showStepBackward() {
        performShowHideNotification(img: stepBackwardImage)
        postAccessibilityNotification(announcement: NSLocalizedString("Step Backward", tableName: "ControlLabels", comment: ""))
    }

    @objc public func showAchievementUnlocked() {
        let config = NSImage.SymbolConfiguration(pointSize: 64, weight: .regular)
        let img = NSImage(systemSymbolName: "trophy.fill", accessibilityDescription: "Achievement Unlocked")?
            .withSymbolConfiguration(config)
        performShowHideNotification(img: img)
        postAccessibilityNotification(announcement: NSLocalizedString("Achievement Unlocked", tableName: "ControlLabels", comment: ""))
    }
    
    // MARK: - Animation
    
    func performShowHideNotification(img: NSImage?) {
        if !self.showNotifications {
            return
        }
        
        CATransaction.begin()
        CATransaction.disableActions()
        self.image = img
        self.layer?.opacity = 0.0
        CATransaction.commit()
        
        self.layer?.add(makeFadeInOutAnimation(), forKey: "fadeInOutAnim")
    }
    
    func makeFadeInOutAnimation() -> CAAnimation {
        let opacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
        opacityAnimation.duration = 1.75
        opacityAnimation.fillMode = .forwards
        opacityAnimation.values = [ 0, 1, 1, 0 ]
        opacityAnimation.keyTimes = [ 0, 0.15, 0.85, 1 ]
        return opacityAnimation
    }
    
    func performNotification(img: NSImage?, enabled: Bool, state: inout Bool) {
        if !self.showNotifications {
            return
        }
        
        if enabled && state {
            return
        }

        guard let layer = self.layer else {
            return
        }

        state = enabled

        var localImg = img
        var localEnabled = enabled

        // Rewind + Fast Forward = Fast Rewind
        if localImg == fastForwardImage && isRewinding {
            return
        }

        // Resume fast forward notification after rewind ends if fast forward is still pressed
        if localImg == rewindImage && !enabled && isFastForwarding {
            localImg = fastForwardImage
            localEnabled = true
        }

        layer.removeAllAnimations()
        if localEnabled {
            CATransaction.begin()
            CATransaction.disableActions()
            CATransaction.commit()
            image = localImg
            layer.add(makeFadeAnimation(from: 0), forKey: "fadeInAnim")
            layer.opacity = 1.0
        } else {
            layer.add(makeFadeAnimation(from: layer.opacity), forKey: "fadeOutAnim")
            layer.opacity = 0.0
        }
    }
    
    func makeFadeAnimation(from: Float) -> CAAnimation {
        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.duration = 0.25
        opacityAnimation.fillMode = .forwards
        opacityAnimation.fromValue = from
        return opacityAnimation
    }
    
    // MARK: - Accessibility
    func postAccessibilityNotification(announcement: String) {
        NSAccessibility.post(element: NSApp.mainWindow as Any,
                        notification: .announcementRequested,
                            userInfo: [.announcement: announcement,
                                           .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
