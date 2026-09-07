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
import OpenEmuBase

// MARK: - Column identifiers

private extension NSUserInterfaceItemIdentifier {
    static let systemColumn  = NSUserInterfaceItemIdentifier("systemColumn")
    static let coreColumn    = NSUserInterfaceItemIdentifier("coreColumn")
    static let versionColumn = NSUserInterfaceItemIdentifier("versionColumn")
    static let actionColumn  = NSUserInterfaceItemIdentifier("actionColumn")

    static let systemCell    = NSUserInterfaceItemIdentifier("systemCell")
    static let coreCell      = NSUserInterfaceItemIdentifier("coreCell")
    static let versionCell   = NSUserInterfaceItemIdentifier("versionCell")
    static let actionCell    = NSUserInterfaceItemIdentifier("actionCell")
}

// MARK: - Data model

private struct SystemEntry {
    let systemIdentifier: String
    let systemName: String
    var cores: [CoreDownload]

    var activeCoreID: String? {
        get { UserDefaults.standard.string(forKey: "defaultCore.\(systemIdentifier)") }
        set { UserDefaults.standard.set(newValue, forKey: "defaultCore.\(systemIdentifier)") }
    }

    var activeCore: CoreDownload? {
        let id = activeCoreID ?? ""
        if let match = cores.first(where: { $0.bundleIdentifier.caseInsensitiveCompare(id) == .orderedSame }) {
            return match
        }
        return cores.first(where: { !$0.canBeInstalled }) ?? cores.first
    }

    var hasMultipleCoreOptions: Bool { cores.count > 1 }
}

// MARK: - Controller

final class PrefCoresController: NSViewController {

    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var warningBanner: NSTextField!

    private var entries: [SystemEntry] = []
    private var coreListObservation: NSKeyValueObservation?

    override func loadView() {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers  = true
        scroll.scrollerStyle       = .overlay
        scroll.borderType = .bezelBorder

        let table = NSTableView()
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 44
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.cornerView = nil
        table.delegate   = self
        table.dataSource = self

        let columns: [(NSUserInterfaceItemIdentifier, String, CGFloat, CGFloat, CGFloat)] = [
            (.systemColumn,  NSLocalizedString("System",      comment: "Cores prefs column"), 180, 120, 260),
            (.coreColumn,    NSLocalizedString("Core",        comment: "Cores prefs column"), 160, 100, 240),
            (.versionColumn, NSLocalizedString("Version",     comment: "Cores prefs column"), 110,  80, 150),
            (.actionColumn,  "Select Core",                                                   160, 120, 10000),
        ]

        for (ident, title, width, minW, maxW) in columns {
            let col = NSTableColumn(identifier: ident)
            col.headerCell.title = title
            col.width    = width
            col.minWidth = minW
            col.maxWidth = maxW
            col.resizingMask = .userResizingMask
            table.addTableColumn(col)
        }

        table.autoresizingMask = [.width]
        scroll.documentView = table
        self.tableView  = table
        self.scrollView = scroll

        let warning = NSTextField(wrappingLabelWithString: "")
        warning.textColor = .systemOrange
        warning.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        warning.isHidden = true
        self.warningBanner = warning

        // NSStackView collapses hidden views to zero height automatically,
        // so the table fills the full space when no collision banner is shown.
        let stack = NSStackView(views: [warning, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 0, right: 8)
        self.view = stack
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        tableView.sizeLastColumnToFit()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        coreListObservation = CoreUpdater.shared.observe(\CoreUpdater.coreList) { [weak self] _, _ in
            self?.rebuildEntries()
        }

        CoreUpdater.shared.checkForNewCores()
        CoreUpdater.shared.checkForUpdates()
        rebuildEntries()

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.rebuildEntries()
        }
    }

    // MARK: - Data

    private func rebuildEntries() {
        DispatchQueue.main.async { [weak self] in
            self?.applyEntries()
        }
    }

    private func applyEntries() {

        let collisions = OECorePlugin.collidingBundleIdentifiers
        if collisions.isEmpty {
            warningBanner.isHidden = true
        } else {
            let names = collisions.sorted().joined(separator: ", ")
            warningBanner.stringValue = "⚠ Duplicate core bundles detected: \(names). Open ~/Library/Application Support/OpenEmu/Cores/ and remove the extra copy of each affected core."
            warningBanner.isHidden = false
        }
        var map: [String: (name: String, cores: [CoreDownload])] = [:]
        for core in CoreUpdater.shared.coreList {
            for sysID in core.systemIdentifiers {
                // Look up the display name fresh from OESystemPlugin at rebuild time.
                // core.systemNames is populated at CoreUpdater init before all system plugins
                // load, so index-matched names are unreliable for multi-system cores.
                let liveName = OESystemPlugin.systemPlugin(forIdentifier: sysID)?.systemName ?? sysID
                let sysName  = displayName(for: sysID, fallback: liveName)
                if map[sysID] == nil { map[sysID] = (name: sysName, cores: []) }
                if !map[sysID]!.cores.contains(where: { $0.bundleIdentifier == core.bundleIdentifier }) {
                    map[sysID]!.cores.append(core)
                }
            }
        }

        entries = map.map { sysID, value in
            SystemEntry(
                systemIdentifier: sysID,
                systemName: value.name,
                cores: value.cores.sorted { $0.name < $1.name }
            )
        }
        .sorted { $0.systemName < $1.systemName }

        tableView.reloadData()
    }

    private func displayName(for sysID: String, fallback: String) -> String {
        // OpenEmu models Game Boy and Game Boy Color as one system (openemu.system.gb);
        // Gambatte handles both. Make the dual coverage explicit in the UI.
        if sysID == "openemu.system.gb" { return "Game Boy / Game Boy Color" }
        guard fallback == sysID else { return fallback }
        let last = sysID.components(separatedBy: ".").last ?? sysID
        return last
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    // MARK: - Actions

    @objc private func actionMenuSelected(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? (row: Int, kind: ActionKind) else { return }
        let row = info.row
        guard row < entries.count else { return }

        switch info.kind {

        case .selectCore(let bundleID):
            entries[row].activeCoreID = bundleID
            tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet([1, 2, 3]))

        case .install, .update:
            guard let core = entries[row].activeCore else { return }
            CoreUpdater.shared.installCoreInBackgroundUserInitiated(core)

        case .check:
            CoreUpdater.shared.checkForNewCores()
            CoreUpdater.shared.checkForUpdates()

        case .revert:
            guard let core = entries[row].activeCore else { return }
            confirmRevert(core: core)

        }
    }

    private func confirmRevert(core: CoreDownload) {
        let alert = NSAlert()
        alert.messageText     = NSLocalizedString("Revert to previous version?", comment: "")
        alert.informativeText = String(
            format: NSLocalizedString("Are you sure you want to revert '%@' to the previous version?", comment: ""),
            core.name)
        alert.addButton(withTitle: NSLocalizedString("Revert", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alert.beginSheetModal(for: view.window!) { response in
            guard response == .alertFirstButtonReturn else { return }
            CoreUpdater.shared.revertCore(bundleID: core.bundleIdentifier) { error in
                DispatchQueue.main.async {
                    if let error = error { NSApp.presentError(error) }
                    else { self.rebuildEntries() }
                }
            }
        }
    }
}

// MARK: - ActionKind

private enum ActionKind {
    case selectCore(bundleID: String)
    case install, update, check, revert
}

// MARK: - NSTableViewDataSource

extension PrefCoresController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? { nil }
}

// MARK: - NSTableViewDelegate

extension PrefCoresController: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 44 }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < entries.count else { return nil }
        let entry = entries[row]
        let ident = tableColumn!.identifier

        switch ident {

        case .systemColumn:
            let cell = makeTextCell(.systemCell)
            cell.textField?.stringValue = entry.systemName
            cell.textField?.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            cell.textField?.textColor = .labelColor
            return cell

        case .coreColumn:
            let cell = makeTextCell(.coreCell)
            if let core = entry.activeCore {
                let supportsRA = OECorePlugin
                    .corePlugin(bundleIdentifier: core.bundleIdentifier)?
                    .supportsRetroAchievements(forSystemIdentifier: entry.systemIdentifier) ?? false
                cell.textField?.stringValue = supportsRA ? "\(core.name) 🏆" : core.name
                cell.textField?.textColor = .labelColor
                cell.toolTip = supportsRA
                    ? NSLocalizedString("This core supports RetroAchievements for this system.",
                                        comment: "Tooltip for the trophy badge in the cores preferences list")
                    : nil
            } else {
                cell.textField?.stringValue = NSLocalizedString("None", comment: "")
                cell.textField?.textColor = .tertiaryLabelColor
            }
            return cell

        case .versionColumn:
            let cell = makeTextCell(.versionCell)
            if let core = entry.activeCore {
                let cur = core.version.isEmpty ? "—" : core.version
                let lat = core.appcastItem?.version ?? cur
                cell.textField?.stringValue = "Ver: \(cur)\nLat: \(lat)"
            } else {
                cell.textField?.stringValue = "—"
            }
            cell.textField?.textColor = .secondaryLabelColor
            cell.textField?.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            return cell

        case .actionColumn:
            return makeActionCell(for: entry, row: row)

        default:
            return nil
        }
    }

    // MARK: - Cell builders

    private func makeTextCell(_ identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let tf = NSTextField(labelWithString: "")
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.maximumNumberOfLines = 2
        tf.lineBreakMode = .byWordWrapping
        cell.addSubview(tf)
        cell.textField = tf
        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func makeActionCell(for entry: SystemEntry, row: Int) -> NSView {
        let cell  = NSTableCellView()
        cell.identifier = .actionCell

        let popup = NSPopUpButton(frame: .zero, pullsDown: true)
        popup.bezelStyle  = .rounded
        popup.controlSize = .small
        popup.font        = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
        popup.translatesAutoresizingMaskIntoConstraints = false

        let menu   = NSMenu()
        let active = entry.activeCore

        // ── Manage installed core ────────────────────────────────────────────
        if let core = active {
            let mgmt: NSMenuItem
            if core.isDownloading {
                mgmt = disabledItem("Downloading…")
            } else if core.canBeInstalled && core.appcastItem == nil {
                mgmt = disabledItem(NSLocalizedString("Unavailable", comment: ""))
            } else if core.canBeInstalled {
                mgmt = makeItem(NSLocalizedString("Install", comment: ""), row: row, kind: .install)
            } else if core.hasUpdate {
                mgmt = makeItem(NSLocalizedString("Update Available", comment: ""), row: row, kind: .update)
            } else if CoreUpdater.shared.hasBackup(bundleID: core.bundleIdentifier) {
                mgmt = makeItem(NSLocalizedString("Revert", comment: ""), row: row, kind: .revert)
            } else {
                mgmt = makeItem(NSLocalizedString("Check for Update", comment: ""), row: row, kind: .check)
            }
            menu.addItem(mgmt)
        } else {
            menu.addItem(disabledItem(NSLocalizedString("No Core", comment: "")))
        }

        // ── Official core picker ─────────────────────────────────────────────
        if entry.hasMultipleCoreOptions {
            if !menu.items.isEmpty { menu.addItem(.separator()) }

            let activeID = entry.activeCoreID
            for core in entry.cores {
                let supportsRA = OECorePlugin
                    .corePlugin(bundleIdentifier: core.bundleIdentifier)?
                    .supportsRetroAchievements(forSystemIdentifier: entry.systemIdentifier) ?? false
                let itemTitle = supportsRA ? "\(core.name) 🏆" : core.name
                let item = makeItem(itemTitle, row: row, kind: .selectCore(bundleID: core.bundleIdentifier))
                item.state = core.bundleIdentifier.caseInsensitiveCompare(activeID ?? "") == .orderedSame ? .on : .off
                menu.addItem(item)
            }
        }

        // Title item (index 0 of a pull-down is the button label)
        let titleLabel: String
        if let core = active {
            if core.isDownloading {
                titleLabel = "Downloading…"
            } else if core.canBeInstalled {
                titleLabel = "Install \(core.name)"
            } else if core.hasUpdate {
                titleLabel = "⬆ \(core.name)"
            } else {
                let supportsRA = OECorePlugin
                    .corePlugin(bundleIdentifier: core.bundleIdentifier)?
                    .supportsRetroAchievements(forSystemIdentifier: entry.systemIdentifier) ?? false
                titleLabel = supportsRA ? "\(core.name) 🏆" : core.name
            }
        } else {
            titleLabel = NSLocalizedString("No Core", comment: "")
        }
        menu.insertItem(NSMenuItem(title: titleLabel, action: nil, keyEquivalent: ""), at: 0)

        popup.menu = menu
        popup.selectItem(at: 0)

        cell.addSubview(popup)
        NSLayoutConstraint.activate([
            popup.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            popup.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            popup.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func makeItem(_ title: String, row: Int, kind: ActionKind) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(actionMenuSelected(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = (row: row, kind: kind)
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}

// MARK: - PreferencePane

extension PrefCoresController: PreferencePane {
    var icon: NSImage? { NSImage(named: "cores_tab_icon") }
    var panelTitle: String { "Cores" }
    var viewSize: NSSize { NSSize(width: 640, height: 480) }
}
