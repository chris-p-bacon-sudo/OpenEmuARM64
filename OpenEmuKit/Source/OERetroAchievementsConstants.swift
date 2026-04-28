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
