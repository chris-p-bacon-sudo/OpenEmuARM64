// Copyright (c) 2026, OpenEmu Team
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

/// Posted by `OpenEmuHelperApp` when the RA token changes.
/// - `userInfo[OERetroAchievementsTokenKey]`: the new token `String`, or absent when logging out.
public extension Notification.Name {
    static let OERetroAchievementsTokenDidChange = Notification.Name("OERetroAchievementsTokenDidChange")
}

/// Keys in the `OERetroAchievementsTokenDidChange` notification's `userInfo` dictionary.
public let OERetroAchievementsTokenKey    = "token"
public let OERetroAchievementsUsernameKey = "username"

/// Posted by `OpenEmuHelperApp` when the user toggles RA hardcore mode.
/// - `userInfo[OEHardcoreEnabledKey]`: the new value as `Bool`.
public extension Notification.Name {
    static let OEHardcoreModeDidChange = Notification.Name("OEHardcoreModeDidChange")
}

/// Key in the `OEHardcoreModeDidChange` notification's `userInfo` dictionary.
public let OEHardcoreEnabledKey = "hardcoreEnabled"

/// Posted by a core plugin when an achievement is earned.
public extension Notification.Name {
    static let OEAchievementUnlocked = Notification.Name("OEAchievementUnlocked")
}

/// Keys in the `OEAchievementUnlocked` notification's `userInfo` dictionary.
public let OEAchievementIDKey          = "id"
public let OEAchievementTitleKey       = "title"
public let OEAchievementDescriptionKey = "description"
public let OEAchievementBadgeURLKey    = "badgeURL"
public let OEAchievementPointsKey      = "points"

/// Posted inside the helper process by a core plugin when the loaded game's
/// RetroAchievements metadata changes. The helper observes this and forwards
/// the payload to the host app through `OEGameCoreOwner`.
public extension Notification.Name {
    static let OERetroAchievementsSessionUpdated = Notification.Name("OERetroAchievementsSessionUpdated")
}

/// Posted by `OEGameDocument` in the host app after the helper forwards a
/// RetroAchievements session metadata update. UI should observe this host-side
/// notification instead of `OERetroAchievementsSessionUpdated` to avoid echoing
/// helper notifications in same-process core-manager mode.
public extension Notification.Name {
    static let OERetroAchievementsSessionDidChange = Notification.Name("OERetroAchievementsSessionDidChange")
}

/// Keys in the RetroAchievements session metadata `userInfo` dictionary.
public let OERetroAchievementsGameIDKey              = "gameID"
public let OERetroAchievementsGameTitleKey           = "gameTitle"
public let OERetroAchievementsGameHashKey            = "gameHash"
public let OERetroAchievementsGameBadgeURLKey        = "gameBadgeURL"
public let OERetroAchievementsUnlockedCountKey       = "unlockedCount"
public let OERetroAchievementsAchievementCountKey    = "achievementCount"
public let OERetroAchievementsUnlockedPointsKey      = "unlockedPoints"
public let OERetroAchievementsTotalPointsKey         = "totalPoints"
public let OERetroAchievementsAchievementsKey        = "achievements"
public let OERetroAchievementsSetsKey                = "sets"
public let OERetroAchievementsSetIDKey               = "setID"
public let OERetroAchievementsSetTitleKey            = "setTitle"
public let OERetroAchievementsSetBadgeURLKey         = "setBadgeURL"
public let OERetroAchievementsSetAchievementCountKey = "setAchievementCount"
public let OERetroAchievementsSetLeaderboardCountKey = "setLeaderboardCount"
public let OERetroAchievementsBucketTitleKey         = "bucketTitle"
public let OERetroAchievementsBucketTypeKey          = "bucketType"
public let OERetroAchievementsStateKey               = "state"
public let OERetroAchievementsTypeKey                = "type"
public let OERetroAchievementsMeasuredProgressKey    = "measuredProgress"
public let OERetroAchievementsMeasuredPercentKey     = "measuredPercent"
public let OERetroAchievementsBadgeLockedURLKey      = "badgeLockedURL"
public let OERetroAchievementsRarityKey              = "rarity"
public let OERetroAchievementsHardcoreRarityKey      = "rarityHardcore"
public let OERetroAchievementsUnlockedKey            = "unlocked"
