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

#import <Foundation/Foundation.h>
#import <string.h>
#import "OERetroAchievementsTransport.h"

static NSString *OEStringFromCString(const char *string)
{
    if (!string) { return @""; }
    NSString *value = [NSString stringWithCString:string encoding:NSUTF8StringEncoding];
    return value ?: @"";
}

static void OEPostSessionStatus(NSString *status, int result, const char *error_message)
{
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[OERASessionStatusKey] = status;
    payload[OERASessionErrorCodeKey] = @(result);

    NSString *message = OEStringFromCString(error_message);
    if (message.length > 0) { payload[OERASessionErrorMessageKey] = message; }

    [[NSNotificationCenter defaultCenter] postNotificationName:OERASessionUpdatedNotification
                                                        object:nil
                                                      userInfo:payload];
}

static BOOL OEIsUnrecognizedGameResult(int result)
{
    // rcheevos currently reports unknown/no-set hashes through these two
    // results. Keep this classification centralized so new upstream result
    // codes can be added in one place if needed.
    return result == RC_NO_GAME_LOADED || result == RC_NOT_FOUND;
}

void oeRetroAchievementsPostSessionLoadFailure(int result, const char *error_message)
{
    NSString *status = OEIsUnrecognizedGameResult(result)
        ? OERASessionStatusUnrecognized
        : OERASessionStatusLoadFailed;
    OEPostSessionStatus(status, result, error_message);
}

void oeRetroAchievementsPostLoginFailure(int result, const char *error_message)
{
    OEPostSessionStatus(OERASessionStatusLoginFailed, result, error_message);
}

static void OEAddAchievementPayload(NSMutableDictionary *payload, const rc_client_achievement_t *achievement)
{
    if (!achievement) { return; }
    payload[OERAEventIDKey] = @(achievement->id);
    payload[OERAEventTitleKey] = OEStringFromCString(achievement->title);
    payload[OERAEventDescriptionKey] = OEStringFromCString(achievement->description);
    payload[OERAEventPointsKey] = @(achievement->points);
    payload[OERAMeasuredProgressKey] = OEStringFromCString(achievement->measured_progress);
    payload[OERAMeasuredPercentKey] = @(achievement->measured_percent);
    if (achievement->badge_url) { payload[OERAEventBadgeURLKey] = OEStringFromCString(achievement->badge_url); }
    if (achievement->badge_locked_url) { payload[OERABadgeLockedURLKey] = OEStringFromCString(achievement->badge_locked_url); }
}

static void OEAddLeaderboardPayload(NSMutableDictionary *payload, const rc_client_leaderboard_t *leaderboard)
{
    if (!leaderboard) { return; }
    payload[OERAEventIDKey] = @(leaderboard->id);
    payload[OERAEventTitleKey] = OEStringFromCString(leaderboard->title);
    payload[OERAEventDescriptionKey] = OEStringFromCString(leaderboard->description);
    if (leaderboard->tracker_value) {
        payload[OERAEventDisplayKey] = OEStringFromCString(leaderboard->tracker_value);
    }
}

void oeRetroAchievementsPostEventNotification(const rc_client_event_t *event,
                                               rc_client_t *client)
{
    (void)client;
    if (!event) { return; }

    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[OERAEventTypeKey] = @(event->type);

    switch (event->type) {
        case RC_CLIENT_EVENT_ACHIEVEMENT_TRIGGERED:
            payload[OERAEventKindKey] = @"achievementUnlocked";
            OEAddAchievementPayload(payload, event->achievement);
            break;
        case RC_CLIENT_EVENT_ACHIEVEMENT_CHALLENGE_INDICATOR_SHOW:
            payload[OERAEventKindKey] = @"challengeShow";
            OEAddAchievementPayload(payload, event->achievement);
            break;
        case RC_CLIENT_EVENT_ACHIEVEMENT_CHALLENGE_INDICATOR_HIDE:
            payload[OERAEventKindKey] = @"challengeHide";
            OEAddAchievementPayload(payload, event->achievement);
            break;
        case RC_CLIENT_EVENT_ACHIEVEMENT_PROGRESS_INDICATOR_SHOW:
            payload[OERAEventKindKey] = @"progressShow";
            OEAddAchievementPayload(payload, event->achievement);
            break;
        case RC_CLIENT_EVENT_ACHIEVEMENT_PROGRESS_INDICATOR_UPDATE:
            payload[OERAEventKindKey] = @"progressUpdate";
            OEAddAchievementPayload(payload, event->achievement);
            break;
        case RC_CLIENT_EVENT_ACHIEVEMENT_PROGRESS_INDICATOR_HIDE:
            payload[OERAEventKindKey] = @"progressHide";
            break;
        case RC_CLIENT_EVENT_LEADERBOARD_STARTED:
            payload[OERAEventKindKey] = @"leaderboardStarted";
            OEAddLeaderboardPayload(payload, event->leaderboard);
            break;
        case RC_CLIENT_EVENT_LEADERBOARD_FAILED:
            payload[OERAEventKindKey] = @"leaderboardFailed";
            OEAddLeaderboardPayload(payload, event->leaderboard);
            break;
        case RC_CLIENT_EVENT_LEADERBOARD_SUBMITTED:
            payload[OERAEventKindKey] = @"leaderboardSubmitted";
            OEAddLeaderboardPayload(payload, event->leaderboard);
            break;
        case RC_CLIENT_EVENT_LEADERBOARD_TRACKER_SHOW:
            payload[OERAEventKindKey] = @"leaderboardTrackerShow";
            if (event->leaderboard_tracker) {
                payload[OERAEventIDKey] = @(event->leaderboard_tracker->id);
                payload[OERAEventDisplayKey] = OEStringFromCString(event->leaderboard_tracker->display);
            }
            break;
        case RC_CLIENT_EVENT_LEADERBOARD_TRACKER_UPDATE:
            payload[OERAEventKindKey] = @"leaderboardTrackerUpdate";
            if (event->leaderboard_tracker) {
                payload[OERAEventIDKey] = @(event->leaderboard_tracker->id);
                payload[OERAEventDisplayKey] = OEStringFromCString(event->leaderboard_tracker->display);
            }
            break;
        case RC_CLIENT_EVENT_LEADERBOARD_TRACKER_HIDE:
            payload[OERAEventKindKey] = @"leaderboardTrackerHide";
            if (event->leaderboard_tracker) { payload[OERAEventIDKey] = @(event->leaderboard_tracker->id); }
            break;
        case RC_CLIENT_EVENT_LEADERBOARD_SCOREBOARD:
            payload[OERAEventKindKey] = @"leaderboardScoreboard";
            if (event->leaderboard_scoreboard) {
                payload[OERAEventIDKey] = @(event->leaderboard_scoreboard->leaderboard_id);
                payload[OERAEventSubmittedScoreKey] = OEStringFromCString(event->leaderboard_scoreboard->submitted_score);
                payload[OERAEventBestScoreKey] = OEStringFromCString(event->leaderboard_scoreboard->best_score);
                payload[OERAEventRankKey] = @(event->leaderboard_scoreboard->new_rank);
                payload[OERAEventTotalEntriesKey] = @(event->leaderboard_scoreboard->num_entries);
            }
            break;
        case RC_CLIENT_EVENT_RESET:
            payload[OERAEventKindKey] = @"resetRequested";
            break;
        case RC_CLIENT_EVENT_GAME_COMPLETED:
            payload[OERAEventKindKey] = @"gameCompleted";
            break;
        case RC_CLIENT_EVENT_SUBSET_COMPLETED:
            payload[OERAEventKindKey] = @"subsetCompleted";
            if (event->subset) {
                payload[OERAEventIDKey] = @(event->subset->id);
                payload[OERAEventTitleKey] = OEStringFromCString(event->subset->title);
                if (event->subset->badge_url) { payload[OERAEventBadgeURLKey] = OEStringFromCString(event->subset->badge_url); }
            }
            break;
        case RC_CLIENT_EVENT_SERVER_ERROR:
            payload[OERAEventKindKey] = @"serverError";
            if (event->server_error) {
                payload[OERAEventErrorMessageKey] = OEStringFromCString(event->server_error->error_message);
                payload[OERAEventAPIKey] = OEStringFromCString(event->server_error->api);
                payload[OERAEventIDKey] = @(event->server_error->related_id);
            }
            break;
        case RC_CLIENT_EVENT_DISCONNECTED:
            payload[OERAEventKindKey] = @"disconnected";
            break;
        case RC_CLIENT_EVENT_RECONNECTED:
            payload[OERAEventKindKey] = @"reconnected";
            break;
        default:
            return;
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:OERAEventNotification
                                                        object:nil
                                                      userInfo:payload];
}

// Bridge a rcheevos HTTP request to NSURLSession.
// This function is passed as the `server_call_function` argument to rc_client_create.
// It must be called from any thread; NSURLSession dispatches its completion handler
// on an internal queue and we forward straight to the rcheevos callback from there.
void oeRetroAchievementsServerCall(const rc_api_request_t *request,
                                    rc_client_server_callback_t callback,
                                    void *callback_data,
                                    rc_client_t *client)
{
    NSString *urlString = [NSString stringWithUTF8String:request->url];
    NSURL    *url       = [NSURL URLWithString:urlString];
    if (!url) {
        rc_api_server_response_t error_response = {
            .body            = "",
            .body_length     = 0,
            .http_status_code = RC_API_SERVER_RESPONSE_CLIENT_ERROR
        };
        callback(&error_response, callback_data);
        return;
    }

    NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:url];

    char rcClause[64] = {0};
    rc_client_get_user_agent_clause(client, rcClause, sizeof(rcClause));

    // rc_client userdata is always the OEGameCore subclass instance.
    // Append core name + version so RA can identify the client per their spec.
    void *userdata = rc_client_get_userdata(client);
    NSString *coreSuffix = @"";
    if (userdata) {
        id coreObject = (__bridge id)userdata;
        NSBundle *coreBundle = [NSBundle bundleForClass:[coreObject class]];
        NSString *name = [coreBundle.bundlePath.lastPathComponent stringByDeletingPathExtension];
        NSString *version = coreBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"0.0.0";
        if (name.length > 0) {
            coreSuffix = [NSString stringWithFormat:@" %@/%@", name, version];
        }
    }

    // RA expects an identifying User-Agent so they can correlate traffic to the host app.
    // Format: OpenEmu-Silicon/<host-version> (macOS <os-version>) rcheevos/<...> <Core>/<ver>
    NSString *hostVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown";
    NSOperatingSystemVersion osv = [[NSProcessInfo processInfo] operatingSystemVersion];
    NSString *osVersion = [NSString stringWithFormat:@"%ld.%ld.%ld", (long)osv.majorVersion, (long)osv.minorVersion, (long)osv.patchVersion];
    NSString *userAgent = [NSString stringWithFormat:@"OpenEmu-Silicon/%@ (macOS %@) %@%@",
                            hostVersion, osVersion, [NSString stringWithUTF8String:rcClause], coreSuffix];
    [urlRequest setValue:userAgent forHTTPHeaderField:@"User-Agent"];

    if (request->post_data) {
        urlRequest.HTTPMethod = @"POST";
        urlRequest.HTTPBody   = [NSData dataWithBytes:request->post_data
                                               length:strlen(request->post_data)];
        if (request->content_type) {
            [urlRequest setValue:[NSString stringWithUTF8String:request->content_type]
              forHTTPHeaderField:@"Content-Type"];
        } else {
            [urlRequest setValue:@"application/x-www-form-urlencoded"
              forHTTPHeaderField:@"Content-Type"];
        }
    } else {
        urlRequest.HTTPMethod = @"GET";
    }

    NSURLSessionDataTask *task =
        [[NSURLSession sharedSession]
            dataTaskWithRequest:urlRequest
              completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error || !data) {
                // Copy into a stack buffer so the message outlives any autorelease
                // pool drain that may occur inside the rcheevos callback.
                char errBuf[256] = {0};
                if (error) {
                    const char *u = error.localizedDescription.UTF8String;
                    if (u) { strncpy(errBuf, u, sizeof(errBuf) - 1); }
                }
                rc_api_server_response_t err = {
                    .body             = errBuf,
                    .body_length      = strlen(errBuf),
                    .http_status_code = RC_API_SERVER_RESPONSE_RETRYABLE_CLIENT_ERROR
                };
                callback(&err, callback_data);
                return;
            }

            if (![response isKindOfClass:NSHTTPURLResponse.class]) {
                const char *message = "Invalid HTTP response";
                rc_api_server_response_t err = {
                    .body             = message,
                    .body_length      = strlen(message),
                    .http_status_code = RC_API_SERVER_RESPONSE_RETRYABLE_CLIENT_ERROR
                };
                callback(&err, callback_data);
                return;
            }

            NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
            rc_api_server_response_t server_response = {
                .body             = (const char *)data.bytes,
                .body_length      = data.length,
                .http_status_code = (int)http.statusCode
            };
            callback(&server_response, callback_data);
        }];

    [task resume];
}
