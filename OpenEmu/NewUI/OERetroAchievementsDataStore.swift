// Copyright (c) 2024, OpenEmu Team
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

import Foundation
import OpenEmuKit

@MainActor
final class OERetroAchievementsDataStore: ObservableObject {

    static let shared = OERetroAchievementsDataStore()

    @Published private(set) var sessionInfoByHash: [String: [String: Any]] = [:]
    private(set) var md5ToHash: [String: String] = [:]

    private let sessionKey = "OERetroAchievementsSessionInfoByHash"
    private let md5Key     = "OERetroAchievementsMD5ToHash"

    init() {
        loadFromDefaults()
        // Use closure form with queue:.main so the handler always runs on MainActor,
        // avoiding data races with the @MainActor-isolated stored properties.
        NotificationCenter.default.addObserver(
            forName: .OERetroAchievementsSessionDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let info = notification.userInfo as? [String: Any] else { return }
            self.handleSessionChange(info, document: notification.object as? OEGameDocument)
        }
    }

    func sessionInfo(forGame game: OEDBGame) -> [String: Any]? {
        let md5 = game.defaultROM?.md5Hash?.lowercased() ?? ""

        if let hash = md5ToHash[md5] {
            return sessionInfoByHash[hash]
        }
        return sessionInfoByHash[md5]
    }

    // MARK: - Private

    private func handleSessionChange(_ info: [String: Any], document: OEGameDocument?) {
        let hash = (info[OERetroAchievementsGameHashKey] as? String ?? "").lowercased()
        guard !hash.isEmpty else { return }

        sessionInfoByHash[hash] = info

        if let md5 = document?.rom.md5, !md5.isEmpty {
            md5ToHash[md5.lowercased()] = hash
        }

        saveToDefaults()
    }

    private func loadFromDefaults() {
        let defaults = UserDefaults.standard
        if let raw = defaults.dictionary(forKey: sessionKey) {
            var rebuilt: [String: [String: Any]] = [:]
            for (k, v) in raw {
                if let dict = v as? [String: Any] { rebuilt[k] = dict }
            }
            sessionInfoByHash = rebuilt
        }
        if let raw = defaults.dictionary(forKey: md5Key) as? [String: String] {
            md5ToHash = raw
        }
    }

    private func saveToDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(sessionInfoByHash as NSDictionary, forKey: sessionKey)
        defaults.set(md5ToHash as NSDictionary, forKey: md5Key)
    }
}
