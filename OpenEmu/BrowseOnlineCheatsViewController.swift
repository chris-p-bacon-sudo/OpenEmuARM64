// Copyright (c) 2026, OpenEmu Team
// Author: Leonardo Kasperavičius
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

final class BrowseOnlineCheatsViewController: NSViewController {

    // MARK: - Document reference
    weak var gameDocument: OEGameDocument?

    // MARK: - Game Info Panel
    private var gameLabel: NSTextField!
    private var serialLabel: NSTextField!
    private var systemLabel: NSTextField!
    private var md5Label: NSTextField!
    private var coreLabel: NSTextField!

    // MARK: - Results Table
    private var resultsTableView: NSTableView!
    private var resultsScrollView: NSScrollView!
    private var loadingSpinner: NSProgressIndicator?
    private var isLoading = false
    private var hasLoaded = false

    /// Fetched cheats kept in memory so filtering can work off them without refetching.
    private var cheats: [DatabaseCheat] = []

    /// Applied to each row's cell so the content matches its column header.
    private var columnAlignments: [NSUserInterfaceItemIdentifier: NSTextAlignment] = [:]

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 480))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let infoPanel = makeGameInfoPanel()
        infoPanel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(infoPanel)

        let filterPanel = makeFilterPanel()
        filterPanel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(filterPanel)

        let resultsScrollView = makeResultsTable()
        resultsScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(resultsScrollView)
        self.resultsScrollView = resultsScrollView

        NSLayoutConstraint.activate([
            infoPanel.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            infoPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            infoPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            filterPanel.topAnchor.constraint(equalTo: infoPanel.bottomAnchor),
            filterPanel.leadingAnchor.constraint(equalTo: infoPanel.leadingAnchor),
            filterPanel.trailingAnchor.constraint(equalTo: infoPanel.trailingAnchor),

            resultsScrollView.topAnchor.constraint(equalTo: filterPanel.bottomAnchor, constant: 12),
            resultsScrollView.leadingAnchor.constraint(equalTo: infoPanel.leadingAnchor),
            resultsScrollView.trailingAnchor.constraint(equalTo: infoPanel.trailingAnchor),
            resultsScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])

        updateGameInfo()
    }

    // MARK: - Results Table

    private func makeResultsTable() -> NSScrollView {
        let tableView = NSTableView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.headerView = NSTableHeaderView()
        tableView.style = .fullWidth
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle

        let columns: [(String, String, CGFloat, NSTextAlignment)] = [
            ("name", NSLocalizedString("Cheat Name", comment: "Browse online cheats table column header"), 302, .left),
            ("provider", NSLocalizedString("Provider", comment: "Browse online cheats table column header"), 120, .center),
            ("status", NSLocalizedString("Status", comment: "Browse online cheats table column header"), 120, .center),
            ("action", NSLocalizedString("Action", comment: "Browse online cheats table column header"), 100, .center),
        ]

        for (index, column) in columns.enumerated() {
            let (identifier, title, width, alignment) = column
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            tableColumn.title = title
            tableColumn.width = width
            tableColumn.headerCell.alignment = alignment

            if index == 0 {
                tableColumn.minWidth = 150
                tableColumn.maxWidth = .greatestFiniteMagnitude
                tableColumn.resizingMask = .autoresizingMask
            } else {
                // Locked so the first column is the only one that absorbs width changes.
                tableColumn.minWidth = width
                tableColumn.maxWidth = width
                tableColumn.resizingMask = []
            }

            tableView.addTableColumn(tableColumn)
            columnAlignments[tableColumn.identifier] = alignment
        }

        resultsTableView = tableView

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder

        return scrollView
    }

    // MARK: - Filter Panel

    // TODO: populate with the controls that filter the results table.
    private func makeFilterPanel() -> NSBox {
        let box = NSBox()
        box.titlePosition = .noTitle
        box.contentView?.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return box
    }

    // MARK: - Game Info Panel

    private func makeGameInfoPanel() -> NSBox {
        let box = NSBox()
        box.titlePosition = .noTitle
        // Draws nothing, so the panel reads as part of the window rather than a second card.
        box.isTransparent = true

        let gameTitle = makeTitleLabel(NSLocalizedString("Game", comment: "Browse online cheats info label"), width: 60)
        gameLabel = makeValueLabel(width: 280)
        let md5Title = makeTitleLabel(NSLocalizedString("MD5", comment: "Browse online cheats info label"), width: 40)
        md5Label = makeValueLabel(width: 220)

        let systemTitle = makeTitleLabel(NSLocalizedString("System", comment: "Browse online cheats info label"), width: 60)
        systemLabel = makeValueLabel(width: 140)
        let coreTitle = makeTitleLabel(NSLocalizedString("Core", comment: "Browse online cheats info label"), width: 60)
        coreTitle.alignment = .right
        coreLabel = makeValueLabel(width: 140)
        let serialTitle = makeTitleLabel(NSLocalizedString("Version", comment: "Browse online cheats info label"), width: 60)
        serialTitle.alignment = .right
        serialLabel = makeValueLabel(width: 140)

        let outerStack = NSStackView()
        outerStack.orientation = .vertical
        outerStack.alignment = .leading
        outerStack.spacing = 6
        outerStack.translatesAutoresizingMaskIntoConstraints = false

        outerStack.addArrangedSubview(makeInfoRow(cells: [gameTitle, gameLabel, md5Title, md5Label],
                                                 gapsAfter: [gameLabel]))
        outerStack.addArrangedSubview(makeInfoRow(cells: [systemTitle, systemLabel, coreTitle, coreLabel, serialTitle, serialLabel],
                                                 gapsAfter: [systemLabel, coreLabel]))

        box.contentView?.addSubview(outerStack)
        if let contentView = box.contentView {
            NSLayoutConstraint.activate([
                outerStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
                outerStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
                outerStack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -8),
                outerStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            ])
        }

        return box
    }

    /// `gapsAfter` marks the views that end a field, so the wider gap separates
    /// fields rather than a title from its own value.
    private func makeInfoRow(cells: [NSView], gapsAfter: [NSView] = []) -> NSStackView {
        let row = NSStackView(views: cells)
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.distribution = .fill
        row.spacing = 4
        gapsAfter.forEach { row.setCustomSpacing(20, after: $0) }
        return row
    }

    private func makeTitleLabel(_ title: String, width: CGFloat) -> NSTextField {
        let label = makeInfoLabel(width: width)
        label.stringValue = "\(title):"
        label.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeValueLabel(width: CGFloat) -> NSTextField {
        let label = makeInfoLabel(width: width)
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        return label
    }

    private func makeInfoLabel(width: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.cell?.truncatesLastVisibleLine = true
        // AppKit shows this only while the text is actually clipped.
        label.allowsExpansionToolTips = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
        return label
    }

    private func updateGameInfo() {
        guard let document = gameDocument else { return }
        let placeholder = "—"
        gameLabel.stringValue = document.rom.game?.displayName ?? placeholder
        md5Label.stringValue = document.rom.md5Hash ?? placeholder
        systemLabel.stringValue = document.systemPlugin.systemName
        coreLabel.stringValue = document.corePlugin.displayName
        serialLabel.stringValue = document.rom.serial ?? placeholder
        view.needsLayout = true
    }

    // MARK: - Loading Indicator

    private func showLoadingIndicator() {
        isLoading = true

        if loadingSpinner == nil {
            let spinner = NSProgressIndicator()
            spinner.style = .spinning
            spinner.controlSize = .regular
            spinner.translatesAutoresizingMaskIntoConstraints = false
            resultsScrollView.superview?.addSubview(spinner)
            NSLayoutConstraint.activate([
                spinner.centerXAnchor.constraint(equalTo: resultsScrollView.centerXAnchor),
                spinner.centerYAnchor.constraint(equalTo: resultsScrollView.centerYAnchor),
            ])
            loadingSpinner = spinner
        }
        loadingSpinner?.startAnimation(nil)
        loadingSpinner?.isHidden = false
        resultsTableView.isEnabled = false
    }

    private func hideLoadingIndicator() {
        isLoading = false
        loadingSpinner?.stopAnimation(nil)
        loadingSpinner?.isHidden = true
        resultsTableView.isEnabled = true
    }

    // MARK: - Online Cheats

    func fetchOnlineCheats() {
        guard !isLoading, !hasLoaded else { return }
        guard let document = gameDocument else { return }
        guard let md5 = document.rom.md5Hash else { return }
        let systemID = document.systemPlugin.systemIdentifier
        let coreID = document.corePlugin.bundleIdentifier
        let serial = document.rom.serial
        let gameName = document.rom.game?.displayName

        showLoadingIndicator()

        Task {
            do {
                let results = try await CheatDatabaseService.shared.cheats(forMD5: md5, serial: serial, gameName: gameName, systemIdentifier: systemID, coreIdentifier: coreID)
                cheats = results.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                hasLoaded = true
            } catch {
                NSLog("[Cheats] Browse Online failed: %@", error.localizedDescription)
                cheats = []
            }
            resultsTableView.reloadData()
            hideLoadingIndicator()
        }
    }
}

// MARK: - Table Data Source

extension BrowseOnlineCheatsViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        cheats.count
    }
}

// MARK: - Table Delegate

extension BrowseOnlineCheatsViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let identifier = tableColumn?.identifier, row < cheats.count else { return nil }
        let cheat = cheats[row]

        let cellID = NSUserInterfaceItemIdentifier("BrowseOnlineCheatsCell")
        let cell: NSTextField
        if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTextField {
            cell = existing
        } else {
            cell = NSTextField(labelWithString: "")
            cell.identifier = cellID
            cell.lineBreakMode = .byTruncatingTail
            cell.maximumNumberOfLines = 1
            cell.cell?.truncatesLastVisibleLine = true
            cell.allowsExpansionToolTips = true
        }

        switch identifier.rawValue {
        case "name":
            cell.stringValue = cheat.name
        case "provider":
            cell.stringValue = cheat.providerName
        default:
            cell.stringValue = ""
        }
        cell.alignment = columnAlignments[identifier] ?? .left

        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        false
    }
}
