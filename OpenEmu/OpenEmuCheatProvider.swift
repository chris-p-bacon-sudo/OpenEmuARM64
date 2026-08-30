// Copyright (c) 2026, OpenEmu Team
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted under the BSD 2-Clause license.

import Foundation
import os.log

private let log = Logger(subsystem: "org.openemu.OpenEmu", category: "OpenEmuCheatProvider")

/// Provides cheats from the bundled cheats-database.xml file.
final class OpenEmuCheatProvider: CheatDatabaseProvider {

    let name = "OpenEmu"

    private var cache: [String: [DatabaseCheat]] = [:]

    func supportsSystem(_ systemIdentifier: String) -> Bool {
        loadIfNeeded()
        return database.keys.contains(systemIdentifier)
    }

    func cheats(forMD5 md5: String, systemIdentifier: String) async throws -> [DatabaseCheat] {
        loadIfNeeded()
        return database[systemIdentifier]?[md5.lowercased()] ?? []
    }

    // MARK: - XML Parsing

    // systemIdentifier → [lowercased MD5 → [DatabaseCheat]]
    private var database: [String: [String: [DatabaseCheat]]] = [:]
    private var loaded = false

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true

        guard let url = Bundle.main.url(forResource: "cheats-database", withExtension: "xml"),
              let data = try? Data(contentsOf: url)
        else {
            log.warning("cheats-database.xml not found in app bundle")
            return
        }

        let parser = XMLParser(data: data)
        let delegate = CheatXMLParserDelegate(providerName: name)
        parser.delegate = delegate
        parser.parse()
        database = delegate.result
        let totalCheats = database.values.flatMap(\.values).flatMap({ $0 }).count
        log.info("Loaded bundled cheat database: \(totalCheats) cheats")
    }
}

private class CheatXMLParserDelegate: NSObject, XMLParserDelegate {
    let providerName: String
    // systemIdentifier → [lowercased MD5 → [DatabaseCheat]]
    var result: [String: [String: [DatabaseCheat]]] = [:]

    private var currentSystem: String?
    private var currentMD5s: [String] = []
    private var currentCheats: [DatabaseCheat] = []

    init(providerName: String) {
        self.providerName = providerName
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "system":
            currentSystem = attributeDict["id"]
        case "game":
            currentMD5s = []
            currentCheats = []
        case "hash":
            if let md5 = attributeDict["md5"] {
                currentMD5s.append(md5.lowercased())
            }
        case "cheat":
            if let code = attributeDict["code"], let desc = attributeDict["description"], !code.isEmpty {
                currentCheats.append(DatabaseCheat(name: desc, code: code, providerName: providerName))
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName == "game", let system = currentSystem, !currentCheats.isEmpty else { return }
        for md5 in currentMD5s {
            result[system, default: [:]][md5] = currentCheats
        }
    }
}
