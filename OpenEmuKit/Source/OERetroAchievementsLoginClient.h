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

NS_ASSUME_NONNULL_BEGIN

typedef void (^OERetroAchievementsLoginCompletion)(NSString * _Nullable token,
                                                     NSString * _Nullable displayName,
                                                     NSError * _Nullable error);

/// Standalone RetroAchievements password login, used by the account sign-in
/// UI (no emulator core or ROM involved). Goes through the same rc_client
/// transport (`oeRetroAchievementsServerCall`) that in-game sessions use —
/// a real POST request with an RA-compliant User-Agent — instead of a
/// hand-rolled GET request.
@interface OERetroAchievementsLoginClient : NSObject

/// Attempts to log in with a RetroAchievements username/password. Calls
/// `completion` on the main thread exactly once with either a token and
/// display name, or an error.
+ (void)loginWithUsername:(NSString *)username
                  password:(NSString *)password
                completion:(OERetroAchievementsLoginCompletion)completion;

@end

NS_ASSUME_NONNULL_END
