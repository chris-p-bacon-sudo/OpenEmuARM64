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

/// NSNotificationCenter name posted by OpenEmuHelperApp when the RA hardcore mode toggle flips.
/// userInfo key: `OEHardcoreEnabledKey` (NSNumber boolValue).
#define OEHardcoreModeDidChangeNotification @"OEHardcoreModeDidChange"
#define OEHardcoreEnabledKey                @"hardcoreEnabled"

/// NSNotificationCenter name posted by OERetroAchievementsBridge when rcheevos
/// fires a "warning achievement" (id >= RC_CLIENT_ACHIEVEMENT_WARNING_ID,
/// currently 101000001). RA attaches these to sessions whose emulator client
/// isn't on its recognized/hardcore-compliant list. The bridge suppresses the
/// normal OEAchievementUnlockedNotification for these IDs and posts this
/// instead so the host can surface a single, clear notice (placard) explaining
/// hardcore unlocks will land as Softcore until OpenEmu-Silicon is approved.
/// No userInfo.
#define OERAEmulatorUnrecognizedNotification @"OERetroAchievementsEmulatorUnrecognized"

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

/// NSNotificationCenter name posted by a core plugin when RA session metadata changes.
/// Fired after game load succeeds and after each achievement trigger. The helper app
/// observes this and forwards the payload to the host via OEGameCoreOwner.
#define OERASessionUpdatedNotification      @"OERetroAchievementsSessionUpdated"

// Session payload keys — userInfo dictionary for OERASessionUpdatedNotification
#define OERAGameIDKey                @"gameID"
#define OERAGameTitleKey             @"gameTitle"
#define OERAGameHashKey              @"gameHash"
#define OERAGameBadgeURLKey          @"gameBadgeURL"
#define OERAUnlockedCountKey         @"unlockedCount"
#define OERAAchievementCountKey      @"achievementCount"
#define OERAUnlockedPointsKey        @"unlockedPoints"
#define OERATotalPointsKey           @"totalPoints"
#define OERAAchievementsKey          @"achievements"
#define OERASetsKey                  @"sets"
#define OERASetIDKey                 @"setID"
#define OERASetTitleKey              @"setTitle"
#define OERASetBadgeURLKey           @"setBadgeURL"
#define OERASetAchievementCountKey   @"setAchievementCount"
#define OERASetLeaderboardCountKey   @"setLeaderboardCount"
#define OERABucketTitleKey           @"bucketTitle"
#define OERABucketTypeKey            @"bucketType"
#define OERAStateKey                 @"state"
#define OERATypeKey                  @"type"
#define OERAMeasuredProgressKey      @"measuredProgress"
#define OERAMeasuredPercentKey       @"measuredPercent"
#define OERABadgeLockedURLKey        @"badgeLockedURL"
#define OERARarityKey                @"rarity"
#define OERAHardcoreRarityKey        @"rarityHardcore"
#define OERAUnlockedKey              @"unlocked"
#define OERASessionStatusKey         @"sessionStatus"
#define OERASessionErrorCodeKey      @"sessionErrorCode"
#define OERASessionErrorMessageKey   @"sessionErrorMessage"
#define OERASessionStatusUnrecognized @"unrecognized"
#define OERASessionStatusLoginFailed  @"loginFailed"
#define OERASessionStatusLoadFailed   @"loadFailed"

/// NSNotificationCenter name posted by a core plugin when rcheevos emits a gameplay UI event.
/// The helper app observes this and forwards the payload to the host via OEGameCoreOwner.
#define OERAEventNotification        @"OERetroAchievementsEvent"
#define OERAEventTypeKey             @"eventType"
#define OERAEventKindKey             @"eventKind"
#define OERAEventIDKey               @"eventID"
#define OERAEventTitleKey            @"eventTitle"
#define OERAEventDescriptionKey      @"eventDescription"
#define OERAEventBadgeURLKey         @"eventBadgeURL"
#define OERAEventPointsKey           @"eventPoints"
#define OERAEventDisplayKey          @"eventDisplay"
#define OERAEventSubmittedScoreKey   @"eventSubmittedScore"
#define OERAEventBestScoreKey        @"eventBestScore"
#define OERAEventRankKey             @"eventRank"
#define OERAEventTotalEntriesKey     @"eventTotalEntries"
#define OERAEventErrorMessageKey     @"eventErrorMessage"
#define OERAEventAPIKey              @"eventAPI"

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

/**
 * Returns the host app's marketing version (CFBundleShortVersionString) for the
 * RetroAchievements User-Agent. The RA client runs in the emulator helper
 * process, where -[NSBundle mainBundle] does not resolve to OpenEmu.app and
 * reports no version — which RA rejects as non-numeric ("unknown"). This
 * resolves the version from the enclosing .app of the running executable, so
 * the real shipped version is always sent regardless of process. Falls back to
 * the main bundle, then "unknown".
 */
NSString *OEHostAppVersion(void);

/**
 * Posts a property-list-safe OERAEventNotification for rcheevos gameplay UI
 * events. Core event handlers should call this before handling achievement
 * unlocks or refreshing session snapshots.
 */
void oeRetroAchievementsPostEventNotification(const rc_client_event_t *event,
                                               rc_client_t *client);

/**
 * Posts property-list-safe OERASessionUpdatedNotification payloads when
 * login or game identification fails before a normal session snapshot exists.
 */
void oeRetroAchievementsPostSessionLoadFailure(int result, const char *error_message);
void oeRetroAchievementsPostLoginFailure(int result, const char *error_message);

#ifdef __cplusplus
}
#endif

#endif /* OERetroAchievementsTransport_h */
