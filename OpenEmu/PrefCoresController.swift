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

private extension NSUserInterfaceItemIdentifier {
    static let coreColumn    = NSUserInterfaceItemIdentifier("coreColumn")
    static let systemColumn  = NSUserInterfaceItemIdentifier("systemColumn")
    static let versionColumn = NSUserInterfaceItemIdentifier("versionColumn")
    
    static let coreNameCell        = NSUserInterfaceItemIdentifier("coreNameCell")
    static let systemListCell      = NSUserInterfaceItemIdentifier("systemListCell")
    static let versionCell         = NSUserInterfaceItemIdentifier("versionCell")
    static let installButtonCell   = NSUserInterfaceItemIdentifier("installBtnCell")
    static let installProgressCell = NSUserInterfaceItemIdentifier("installProgressCell")
}

final class PrefCoresController: NSViewController {

    @IBOutlet var coresTableView: NSTableView!

    var coreListObservation: NSKeyValueObservation?

    override func viewDidLoad() {
        super.viewDidLoad()

        coreListObservation = CoreUpdater.shared.observe(\CoreUpdater.coreList) { [weak self] _, _ in
            self?.coresTableView.reloadData()
        }
        CoreUpdater.shared.checkForNewCores()   // TODO: check error from completion handler
        CoreUpdater.shared.checkForUpdates()

        for column in coresTableView.tableColumns {
            switch column.identifier {
            case .coreColumn:
                column.headerCell.title = NSLocalizedString("Core", comment: "Cores preferences, column header")
            case .systemColumn:
                column.headerCell.title = NSLocalizedString("System", comment: "Cores preferences, column header")
            case .versionColumn:
                column.headerCell.title = NSLocalizedString("Version", comment: "Cores preferences, column header")
            default:
                break
            }
        }

        // Add "Action" table column programmatically if not exists
        let actionColumnIdentifier = NSUserInterfaceItemIdentifier("actionColumn")
        if coresTableView.tableColumn(withIdentifier: actionColumnIdentifier) == nil {
            let column = NSTableColumn(identifier: actionColumnIdentifier)
            column.headerCell.title = NSLocalizedString("Action", comment: "Cores preferences, column header")
            column.width = 70
            column.minWidth = 60
            column.maxWidth = 100
            column.resizingMask = .userResizingMask
            coresTableView.addTableColumn(column)
        }

        coresTableView.delegate = self

        // Reload after appcasts finish fetching so Unavailable/Install states settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.coresTableView.reloadData()
        }
    }
    
    @IBAction func updateOrInstall(_ sender: NSButton) {
        let row = coresTableView.row(for: sender)
        guard row > -1 else { return }
        updateOrInstallItem(row)
    }
    
    @IBAction func revertCore(_ sender: NSButton) {
        let row = coresTableView.row(for: sender)
        guard row > -1 else { return }
        let plugin = coreDownload(row)
        
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Revert to previous version?", comment: "")
        alert.informativeText = String(format: NSLocalizedString("Are you sure you want to revert '%@' to the previous version?", comment: ""), plugin.name)
        alert.addButton(withTitle: NSLocalizedString("Revert", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        
        alert.beginSheetModal(for: self.view.window!) { response in
            if response == .alertFirstButtonReturn {
                CoreUpdater.shared.revertCore(bundleID: plugin.bundleIdentifier) { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            NSApp.presentError(error)
                        } else {
                            self.coresTableView.reloadData()
                        }
                    }
                }
            }
        }
    }
    
    private func updateOrInstallItem(_ row: Int) {
        CoreUpdater.shared.installCoreInBackgroundUserInitiated(coreDownload(row))
    }
    
    private func coreDownload(_ row: Int) -> CoreDownload {
        return CoreUpdater.shared.coreList[row]
    }
}

// MARK: - NSTableView DataSource

extension PrefCoresController: NSTableViewDataSource {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return CoreUpdater.shared.coreList.count
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        
        let plugin = coreDownload(row)
        let ident = tableColumn!.identifier
        
        if ident == .coreColumn {
            return plugin.name
            
        } else if ident == .systemColumn {
            let latestVersion = plugin.appcastItem?.version ?? plugin.version
            return "\(plugin.systemNames.joined(separator: ", "))\n(Cur: \(plugin.version), Lat: \(latestVersion))"
            
        } else if ident == .versionColumn {
            if plugin.isDownloading {
                return nil
            } else if plugin.canBeInstalled {
                return NSLocalizedString("Install", comment: "Install Core")
            } else if plugin.hasUpdate {
                return NSLocalizedString("Update", comment: "Update Core")
            } else {
                if let date = plugin.appcastItem?.pubDate {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    return "\(plugin.version) (\(formatter.string(from: date)))"
                }
                return plugin.version
            }
        }
        return nil
    }
}

// MARK: - NSTableView Delegate

extension PrefCoresController: NSTableViewDelegate {
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 44.0 // Increased height for better readability
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        
        let ident = tableColumn!.identifier
        let plugin = coreDownload(row)
        
        if ident == .coreColumn {
            let view = tableView.makeView(withIdentifier: .coreNameCell, owner: self) as! NSTableCellView
            let color: NSColor = plugin.canBeInstalled ? .disabledControlTextColor : .labelColor
            view.textField!.stringValue = plugin.name
            view.textField!.textColor = color
            return view
            
        } else if ident == .systemColumn {
            let view = tableView.makeView(withIdentifier: .systemListCell, owner: self) as! NSTableCellView
            let color: NSColor = plugin.canBeInstalled ? .disabledControlTextColor : .labelColor
            view.textField!.stringValue = plugin.systemNames.joined(separator: ", ")
            view.textField!.textColor = color
            return view
            
        } else if ident == .versionColumn {
            
            let view = tableView.makeView(withIdentifier: .systemListCell, owner: self) as! NSTableCellView
            let currentVer = plugin.version
            let latestVer = plugin.appcastItem?.version ?? currentVer
            view.textField?.stringValue = "Ver: \(currentVer)\nLat: \(latestVer)"
            view.textField?.textColor = .secondaryLabelColor
            return view
            
        } else if ident == NSUserInterfaceItemIdentifier("actionColumn") {
             
            let view = NSTableCellView()
            let button = NSButton(title: "", target: self, action: nil)
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
            button.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(button)
            
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                button.widthAnchor.constraint(greaterThanOrEqualToConstant: 64)
            ])

             if plugin.isDownloading {
                button.title = "..."
                button.isEnabled = false
            } else if plugin.canBeInstalled && plugin.appcastItem == nil {
                button.title = NSLocalizedString("Unavailable", comment: "")
                button.isEnabled = false
            } else if plugin.canBeInstalled {
                button.title = NSLocalizedString("Install", comment: "")
                button.action = #selector(updateOrInstall(_:))
            } else if plugin.hasUpdate {
                button.title = NSLocalizedString("Update", comment: "")
                button.action = #selector(updateOrInstall(_:))
            } else if CoreUpdater.shared.hasBackup(bundleID: plugin.bundleIdentifier) {
                button.title = NSLocalizedString("Revert", comment: "")
                button.action = #selector(revertCore(_:))
            } else {
                button.title = NSLocalizedString("Check", comment: "")
                button.action = #selector(updateOrInstall(_:))
            }
            
            return view
        }
        return nil
    }
    
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return false
    }
}

// MARK: - PreferencePane

extension PrefCoresController: PreferencePane {
    
    var icon: NSImage? { NSImage(named: "cores_tab_icon") }
    
    var panelTitle: String { "Cores" }
    
    var viewSize: NSSize { view.fittingSize }
}
