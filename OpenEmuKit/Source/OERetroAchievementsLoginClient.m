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

#import "OERetroAchievementsLoginClient.h"
#import "OERetroAchievementsTransport.h"
#include <rc_client.h>

static NSString *const OERetroAchievementsLoginErrorDomain = @"org.openemu.RetroAchievementsLogin";

// Login never reads emulator memory — this client isn't attached to a core or ROM.
static uint32_t oe_ra_login_read_memory(uint32_t address, uint8_t *buffer,
                                         uint32_t num_bytes, rc_client_t *client)
{
    (void)address; (void)buffer; (void)num_bytes; (void)client;
    return 0;
}

static void oe_ra_login_callback(int result, const char *error_message,
                                  rc_client_t *client, void *userdata)
{
    OERetroAchievementsLoginCompletion completion = (__bridge_transfer OERetroAchievementsLoginCompletion)userdata;

    NSString *token = nil;
    NSString *displayName = nil;
    NSError *error = nil;

    if (result == RC_OK) {
        const rc_client_user_t *user = rc_client_get_user_info(client);
        if (user && user->token && user->token[0] != '\0') {
            token = @(user->token);
            displayName = user->display_name ? @(user->display_name) : nil;
        } else {
            error = [NSError errorWithDomain:OERetroAchievementsLoginErrorDomain
                                         code:result
                                     userInfo:@{NSLocalizedDescriptionKey: @"Login succeeded but RetroAchievements returned no token."}];
        }
    } else {
        NSString *message = (error_message && error_message[0] != '\0')
            ? @(error_message)
            : @"Invalid user/password combination.";
        error = [NSError errorWithDomain:OERetroAchievementsLoginErrorDomain
                                     code:result
                                 userInfo:@{NSLocalizedDescriptionKey: message}];
    }

    rc_client_destroy(client);

    dispatch_async(dispatch_get_main_queue(), ^{
        completion(token, displayName, error);
    });
}

@implementation OERetroAchievementsLoginClient

+ (void)loginWithUsername:(NSString *)username
                  password:(NSString *)password
                completion:(OERetroAchievementsLoginCompletion)completion
{
    rc_client_t *client = rc_client_create(oe_ra_login_read_memory, oeRetroAchievementsServerCall);

    OERetroAchievementsLoginCompletion completionCopy = [completion copy];
    void *userdata = (__bridge_retained void *)completionCopy;

    rc_client_begin_login_with_password(client, username.UTF8String, password.UTF8String,
                                         oe_ra_login_callback, userdata);
}

@end
