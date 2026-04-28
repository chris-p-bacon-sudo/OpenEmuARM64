// Copyright (c) 2026, OpenEmu Team
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in the
//       documentation and/or other materials provided with the distribution.
//     * Neither the name of the OpenEmu Team nor the names of its contributors
//       may be used to endorse or promote products derived from this software
//       without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY EXPRESS OR
// IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
// OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
// IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY DIRECT, INDIRECT,
// INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
// NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
// THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#ifndef OERetroAchievementsTransport_h
#define OERetroAchievementsTransport_h

#include <rc_client.h>

/// NSNotificationCenter name posted by OpenEmuHelperApp when the RA token changes.
/// userInfo keys: `OERetroAchievementsTokenKey` (NSString token) and
/// `OERetroAchievementsUsernameKey` (NSString username), or absent on logout.
#define OERetroAchievementsTokenDidChangeNotification @"OERetroAchievementsTokenDidChange"
#define OERetroAchievementsTokenKey                   @"token"
#define OERetroAchievementsUsernameKey                @"username"

/// NSNotificationCenter name posted by a core plugin when an achievement is unlocked.
/// userInfo keys: `OEAchievementIDKey` (NSNumber UInt32), `OEAchievementTitleKey` (NSString),
/// `OEAchievementDescriptionKey` (NSString), `OEAchievementBadgeURLKey` (NSString),
/// `OEAchievementPointsKey` (NSNumber UInt32).
#define OEAchievementUnlockedNotification   @"OEAchievementUnlocked"
#define OEAchievementIDKey                  @"id"
#define OEAchievementTitleKey               @"title"
#define OEAchievementDescriptionKey         @"description"
#define OEAchievementBadgeURLKey            @"badgeURL"
#define OEAchievementPointsKey              @"points"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * rc_client_server_call_t implementation that bridges rcheevos HTTP requests
 * to NSURLSession. Pass this function as the second argument to rc_client_create.
 */
void oeRetroAchievementsServerCall(const rc_api_request_t *request,
                                    rc_client_server_callback_t callback,
                                    void *callback_data,
                                    rc_client_t *client);

#ifdef __cplusplus
}
#endif

#endif /* OERetroAchievementsTransport_h */
