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

// MARK: - RetroArch core model

private struct RetroArchCore {
    let coreName: String       // "mGBA"
    let displayName: String    // "mGBA (RetroArch)"
    let dylibURL: URL
    let systemIDs: [String]    // OE system identifiers
    let requiresHWRender: Bool // true → needs OpenGL/Vulkan context the bridge can't yet provide

    var pluginName: String { "\(coreName)-RetroArch" }

    var bundleIdentifier: String {
        let plistURL = installedPluginURL.appendingPathComponent("Contents/Info.plist")
        if let data = try? Data(contentsOf: plistURL),
           let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
           let id = plist["CFBundleIdentifier"] as? String {
            return id
        }
        return "org.openemu.\(pluginName)"
    }

    var installedPluginURL: URL {
        let coresDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OpenEmu/Cores")
        return coresDir.appendingPathComponent("\(pluginName).oecoreplugin")
    }

    var isPluginInstalled: Bool {
        FileManager.default.fileExists(atPath: installedPluginURL.path)
    }
}

// MARK: - Data model

private struct SystemEntry {
    let systemIdentifier: String
    let systemName: String
    var cores: [CoreDownload]
    var retroArchCores: [RetroArchCore] = []

    var activeCoreID: String? {
        get { UserDefaults.standard.string(forKey: "defaultCore.\(systemIdentifier)") }
        set { UserDefaults.standard.set(newValue, forKey: "defaultCore.\(systemIdentifier)") }
    }

    var activeCore: CoreDownload? {
        let id = activeCoreID ?? ""
        if let match = cores.first(where: { $0.bundleIdentifier.caseInsensitiveCompare(id) == .orderedSame }) {
            return match
        }
        // Don't fall back if the active selection is a RetroArch core.
        if retroArchCores.contains(where: { $0.bundleIdentifier.caseInsensitiveCompare(id) == .orderedSame }) {
            return nil
        }
        return cores.first(where: { !$0.canBeInstalled }) ?? cores.first
    }

    var activeRetroArchCore: RetroArchCore? {
        let id = activeCoreID ?? ""
        return retroArchCores.first(where: { $0.bundleIdentifier.caseInsensitiveCompare(id) == .orderedSame })
    }

    var hasMultipleCoreOptions: Bool { (cores.count + retroArchCores.count) > 1 }
}

// MARK: - Controller

final class PrefCoresController: NSViewController {

    private var tableView: NSTableView!
    private var scrollView: NSScrollView!

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
        self.view = scroll
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
        let allRetroArch = scanRetroArchCores()

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
            var entry = SystemEntry(
                systemIdentifier: sysID,
                systemName: value.name,
                cores: value.cores.sorted { $0.name < $1.name }
            )
            entry.retroArchCores = deduplicatedRetroArchCores(allRetroArch.filter { $0.systemIDs.contains(sysID) })
            return entry
        }
        .sorted { $0.systemName < $1.systemName }

        // Add rows for systems that only exist via RA cores (installed or not).
        // Group all RA cores for the same sysID into one row.
        var extraMap: [String: [RetroArchCore]] = [:]
        for raCore in allRetroArch {
            for sysID in raCore.systemIDs where !entries.contains(where: { $0.systemIdentifier == sysID }) {
                extraMap[sysID, default: []].append(raCore)
            }
        }
        for (sysID, raCores) in extraMap {
            var entry = SystemEntry(systemIdentifier: sysID, systemName: displayName(for: sysID, fallback: sysID), cores: [])
            entry.retroArchCores = deduplicatedRetroArchCores(raCores)
            entries.append(entry)
        }

        entries.sort { $0.systemName < $1.systemName }
        tableView.reloadData()
    }

    private func deduplicatedRetroArchCores(_ cores: [RetroArchCore]) -> [RetroArchCore] {
        var seen: [String: RetroArchCore] = [:]
        for core in cores {
            if let existing = seen[core.displayName] {
                // Prefer the installed variant over an uninstalled duplicate
                if core.isPluginInstalled && !existing.isPluginInstalled {
                    seen[core.displayName] = core
                }
            } else {
                seen[core.displayName] = core
            }
        }
        return seen.values.sorted { $0.displayName < $1.displayName }
    }

    private func displayName(for sysID: String, fallback: String) -> String {
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

        case .addRetroArch(let raCore):
            entries[row].activeCoreID = raCore.bundleIdentifier
            tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet([1, 2, 3]))
            if !raCore.isPluginInstalled {
                installRetroArchPlugin(raCore) { [weak self] error in
                    DispatchQueue.main.async {
                        if let error = error {
                            NSApp.presentError(error)
                        } else {
                            self?.enableSystems(for: raCore.systemIDs)
                            self?.rebuildEntries()
                        }
                    }
                }
            } else {
                // Plugin already on disk — ensure the system is visible without a restart.
                enableSystems(for: raCore.systemIDs)
            }
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
    case addRetroArch(RetroArchCore)
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
            if let ra = entry.activeRetroArchCore {
                cell.textField?.stringValue = ra.displayName
                cell.textField?.textColor = .secondaryLabelColor
            } else if let core = entry.activeCore {
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
            } else if entry.activeRetroArchCore != nil {
                cell.textField?.stringValue = "RetroArch"
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
        let activeRA = entry.activeRetroArchCore

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
        } else if activeRA == nil {
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

            // ── RetroArch cores ──────────────────────────────────────────────
            if !entry.retroArchCores.isEmpty {
                menu.addItem(.separator())

                for raCore in entry.retroArchCores {
                    var label = raCore.isPluginInstalled ? raCore.displayName : "Add \(raCore.displayName)"
                    if raCore.requiresHWRender { label += " — not yet supported" }
                    let item  = makeItem(label, row: row, kind: .addRetroArch(raCore))
                    item.state = raCore.bundleIdentifier.caseInsensitiveCompare(activeID ?? "") == .orderedSame ? .on : .off
                    menu.addItem(item)
                }
            }
        } else if !entry.retroArchCores.isEmpty && entry.cores.isEmpty {
            // Only RetroArch options exist for this system.
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            let activeID = entry.activeCoreID
            for raCore in entry.retroArchCores {
                var label = raCore.isPluginInstalled ? raCore.displayName : "Add \(raCore.displayName)"
                if raCore.requiresHWRender { label += " — not yet supported" }
                let item  = makeItem(label, row: row, kind: .addRetroArch(raCore))
                item.state = raCore.bundleIdentifier.caseInsensitiveCompare(activeID ?? "") == .orderedSame ? .on : .off
                menu.addItem(item)
            }
        }

        // Title item (index 0 of a pull-down is the button label)
        let titleLabel: String
        if let ra = activeRA {
            titleLabel = ra.displayName
        } else if let core = active {
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

// MARK: - RetroArch scanner

extension PrefCoresController {

    // Maps upstream RetroArch `.info` `systemid` values to OE system identifiers.
    // Note: many upstream `systemid`s (commodore_c128, commodore_vic20, commodore_plus4,
    // commodore_pet, commodore_cbm2, commodore_cbm5x0, commodore_c64_supercpu,
    // commodore_c64dtv, atari_st, apple_ii, mac68k, dos, pc_88, pc_98, scummvm,
    // 3ds, xbox, model3, mess, etc.) are intentionally absent because OE has no
    // SystemPlugin for those systems — silently dropping them is correct.
    private static let systemIDMap: [String: [String]] = [
        // Nintendo
        "game_boy_advance":      ["openemu.system.gba"],
        "game_boy":              ["openemu.system.gb"],   // GBC ROMs use the GB system in OE
        "super_nes":             ["openemu.system.snes"],
        "nes":                   ["openemu.system.nes"],
        "nintendo_64":           ["openemu.system.n64"],
        "nds":                   ["openemu.system.nds"],  // OE uses "nds", not "ds"
        "nintendo_ds":           ["openemu.system.nds"],
        "gamecube":              ["openemu.system.gc", "openemu.system.wii"],  // Dolphin handles both
        "wii":                   ["openemu.system.wii"],
        "virtual_boy":           ["openemu.system.vb"],
        // TODO: "game_and_watch" — no SystemPlugin for Game & Watch in OE; leaving
        // it unmapped until that plugin lands so the install doesn't silently fail.
        "pokemon_mini":          ["openemu.system.pokemonmini"],
        // Sony
        "playstation":           ["openemu.system.psx"],
        "playstation_2":         ["openemu.system.ps2"],
        "playstation2":          ["openemu.system.ps2"],  // alternate spelling used by some cores
        "playstation_portable":  ["openemu.system.psp"],
        // Sega
        "dreamcast":             ["openemu.system.dc"],
        "sega_genesis":          ["openemu.system.sg"],   // OE uses "sg", not "genesis"
        "sega_mega_drive":       ["openemu.system.sg"],
        "mega_drive":            ["openemu.system.sg"],   // used by Genesis Plus GX, BlastEm, PicoDrive
        "sega_game_gear":        ["openemu.system.gg"],
        "game_gear":             ["openemu.system.gg"],
        "sega_master_system":    ["openemu.system.sms"],
        "master_system":         ["openemu.system.sms"],  // used by Gearsystem, SMS Plus GX
        "sega_saturn":           ["openemu.system.saturn"],
        "sega_cd":               ["openemu.system.scd"],
        "mega_cd":               ["openemu.system.scd"],  // alternate name used by some cores
        "sg-1000":               ["openemu.system.sg1000"],
        // Atari
        "atari_2600":            ["openemu.system.2600"],
        "atari_5200":            ["openemu.system.5200"],
        "atari_7800":            ["openemu.system.7800"],
        "atari_lynx":            ["openemu.system.lynx"],
        "lynx":                  ["openemu.system.lynx"],
        "atari_jaguar":          ["openemu.system.jaguar"],  // used by Virtual Jaguar RA
        "jaguar":                ["openemu.system.jaguar"],
        // NEC
        "pc_engine":             ["openemu.system.pce"],
        "pc_engine_cd":          ["openemu.system.pcecd"],
        "pc_fx":                 ["openemu.system.pcfx"],   // Beetle PC-FX
        // SNK
        "neo_geo_pocket":        ["openemu.system.ngp"],
        "neo_geo_pocket_color":  ["openemu.system.ngp"],
        // Bandai
        "wonderswan":            ["openemu.system.ws"],
        "wonderswan_color":      ["openemu.system.ws"],
        // Other consoles
        "3do":                   ["openemu.system.3do"],
        "colecovision":          ["openemu.system.colecovision"],
        "intellivision":         ["openemu.system.intellivision"],
        "intv":                  ["openemu.system.intellivision"],  // alternate spelling used by some cores
        "odyssey2":              ["openemu.system.odyssey2"],
        "supervision":           ["openemu.system.sv"],
        "vectrex":               ["openemu.system.vectrex"],
        // Commodore / home computers
        "commodore_c64":         ["openemu.system.c64"],
        "commodore_c64sc":       ["openemu.system.c64"],    // VICE x64sc
        "commodore_64":          ["openemu.system.c64"],    // alternate spelling used by some cores
        "msx":                   ["openemu.system.msx"],
        // TODO: "amiga" / "commodore_amiga" — no SystemPlugin for Amiga in OE;
        // leaving unmapped (PUAE, Amiberry) until that plugin lands so the
        // install doesn't silently fail with no plugin to register against.
        // Arcade
        "fb_alpha":              ["openemu.system.arcade"],
        "mame":                  ["openemu.system.arcade"],
    ]

    /// Read-only view of the upstream-RA `systemid` → OE system identifier map,
    /// for the startup inventory diagnostic in AppDelegate.
    static var retroArchSystemIDMap: [String: [String]] { systemIDMap }

    private func scanRetroArchCores() -> [RetroArchCore] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let coresDir = home.appendingPathComponent("Library/Application Support/RetroArch/cores")
        let infoDir  = home.appendingPathComponent("Library/Application Support/RetroArch/info")

        guard let files = try? fm.contentsOfDirectory(at: coresDir, includingPropertiesForKeys: nil) else {
            return []
        }

        return files
            .filter { $0.lastPathComponent.hasSuffix("_libretro.dylib") }
            .compactMap { dylib -> RetroArchCore? in
                let stem    = dylib.deletingPathExtension().lastPathComponent  // e.g. "mgba_libretro"
                let infoURL = infoDir.appendingPathComponent("\(stem).info")
                guard let parsed = parseInfoFile(at: infoURL) else { return nil }
                let sysIDs = parsed.systemIDs
                guard !sysIDs.isEmpty else { return nil }
                return RetroArchCore(
                    coreName:         parsed.coreName,
                    displayName:      "\(parsed.coreName) (RetroArch)",
                    dylibURL:         dylib,
                    systemIDs:        sysIDs,
                    requiresHWRender: parsed.requiresHWRender
                )
            }
            .sorted { $0.displayName < $1.displayName }
    }

    private func parseInfoFile(at url: URL) -> (coreName: String, systemIDs: [String], requiresHWRender: Bool)? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var coreName: String?
        var systemID: String?
        var hwRender = false
        for line in text.components(separatedBy: .newlines) {
            let parts = line.components(separatedBy: "=")
            guard parts.count >= 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let val = parts[1...].joined(separator: "=")
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            switch key {
            case "corename": coreName = val
            case "systemid": systemID = val
            case "hw_render": hwRender = (val.lowercased() == "true")
            default: break
            }
        }
        guard let name = coreName, let sid = systemID else { return nil }
        return (name, Self.systemIDMap[sid] ?? [], hwRender)
    }

    // MARK: - Plugin installation

    /// Ensures the `OEDBSystem` for each system identifier is created and enabled, then posts
    /// `OEDBSystemAvailabilityDidChange` so the sidebar and Library pane refresh immediately.
    private func enableSystems(for systemIDs: [String]) {
        guard let context = OELibraryDatabase.default?.mainThreadContext else { return }
        var changed = false
        for sysID in systemIDs {
            guard let plugin = OESystemPlugin.systemPlugin(forIdentifier: sysID) else { continue }
            let system = OEDBSystem.system(for: plugin, in: context)
            // Only auto-enable when the system has never been explicitly configured.
            // If the user deliberately disabled it, respect that choice.
            if system.isEnabledByDefault {
                system.isEnabled = true
                changed = true
            } else if system.isEnabled {
                // Already enabled — just fire the notification so the sidebar refreshes
                // after OECorePlugin.allPlugins gained the new core.
                NotificationCenter.default.post(name: .OEDBSystemAvailabilityDidChange, object: system)
            }
        }
        if changed {
            try? context.save()
        }
    }

    private func installRetroArchPlugin(_ core: RetroArchCore, completion: @escaping (Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self._createPlugin(core)
                // Register the freshly-created bundle in OECorePlugin.allPlugins
                // so pickers (right-click "Play With…", launch dialog) see it
                // immediately instead of after the user restarts OpenEmu.
                _ = try? OECorePlugin.plugin(bundleAtURL: core.installedPluginURL)
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    private func _createPlugin(_ core: RetroArchCore) throws {
        let fm      = FileManager.default
        let plugin  = core.installedPluginURL
        guard !fm.fileExists(atPath: plugin.path) else { return }

        let macOSDir  = plugin.appendingPathComponent("Contents/MacOS")
        let plistURL  = plugin.appendingPathComponent("Contents/Info.plist")
        try fm.createDirectory(at: macOSDir, withIntermediateDirectories: true)

        // Source the stub executable from the canonical bridge bundle inside
        // OpenEmu.app/Contents/Resources/. Falls back to scanning installed
        // native cores only if the bundle hasn't been wired into the app yet
        // (transition-period safety; remove the fallback once shipping).
        let bridgeBin: URL
        if let bundled = bundledBridgeExecutableURL() {
            bridgeBin = bundled
        } else if let template = findTemplateBinary() {
            bridgeBin = template
        } else {
            throw NSError(domain: "OpenEmu", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No bridge bundle or installed OpenEmu core found to seed the plugin executable."
            ])
        }
        let binaryURL = macOSDir.appendingPathComponent(core.pluginName)
        try fm.copyItem(at: bridgeBin, to: binaryURL)

        // Write Info.plist. OEBridgeVersion stamps the stub with the translator
        // version it ships against so the app can refresh stale stubs on launch.
        let plist: [String: Any] = [
            "CFBundleDevelopmentRegion": "English",
            "CFBundleExecutable":        core.pluginName,
            "CFBundleIdentifier":        "org.openemu.\(core.pluginName)",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName":              core.displayName,
            "CFBundlePackageType":       "BNDL",
            "CFBundleShortVersionString":"1.0",
            "CFBundleVersion":           "1",
            "NSPrincipalClass":          "OEGameCoreController",
            "OEGameCoreClass":           "OELibretroCoreTranslator",
            "OELibretroCorePath":        core.dylibURL.path,
            "OEGameCoreName":            core.displayName,
            "OESystemIdentifiers":       core.systemIDs,
            "OEGameCorePlayerCount":     "2",
            "OEBridgeVersion":           OELibretroBridgeVersion,
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: plistURL)

        // Ad-hoc codesign
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments     = ["--force", "--sign", "-", plugin.path]
        try task.run()
        task.waitUntilExit()
    }

    /// URL of the bridge plugin bundle shipped inside OpenEmu.app/Contents/PlugIns/,
    /// or nil if it hasn't been built into this app (e.g. older build before the
    /// bridge target landed). Lives in PlugIns rather than Resources because
    /// Xcode's modern build system rejects copy-from-built-product into Resources
    /// as a dependency cycle when the destination is being processed by the
    /// app target's "Update Info.plist" run-script phase.
    static func bundledBridgePluginURL() -> URL? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/PlugIns/OpenEmuLibretroBridge.oecoreplugin")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func bundledBridgeExecutableURL() -> URL? {
        guard let plugin = Self.bundledBridgePluginURL() else { return nil }
        let exe = plugin.appendingPathComponent("Contents/MacOS/OpenEmuLibretroBridge")
        return FileManager.default.fileExists(atPath: exe.path) ? exe : nil
    }

    private func findTemplateBinary() -> URL? {
        let coresDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OpenEmu/Cores")
        guard let plugins = try? FileManager.default.contentsOfDirectory(
            at: coresDir, includingPropertiesForKeys: nil
        ) else { return nil }

        for plugin in plugins where plugin.pathExtension == "oecoreplugin" {
            let macOS = plugin.appendingPathComponent("Contents/MacOS")
            if let bins = try? FileManager.default.contentsOfDirectory(
                at: macOS, includingPropertiesForKeys: nil
            ), let bin = bins.first {
                return bin
            }
        }
        return nil
    }
}

// MARK: - PreferencePane

extension PrefCoresController: PreferencePane {
    var icon: NSImage? { NSImage(named: "cores_tab_icon") }
    var panelTitle: String { "Cores" }
    var viewSize: NSSize { NSSize(width: 640, height: 480) }
}
