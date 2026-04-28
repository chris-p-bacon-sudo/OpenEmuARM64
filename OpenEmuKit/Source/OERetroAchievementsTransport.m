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
#import <rc_client.h>

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
    NSString *userAgent = [NSString stringWithFormat:@"OpenEmu %@", [NSString stringWithUTF8String:rcClause]];
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
                rc_api_server_response_t err = {
                    .body             = error ? error.localizedDescription.UTF8String : "",
                    .body_length      = 0,
                    .http_status_code = RC_API_SERVER_RESPONSE_CLIENT_ERROR
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
