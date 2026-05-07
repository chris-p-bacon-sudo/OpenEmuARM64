// Copyright (c) 2022, OpenEmu Team
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
import Sentry

// Initialize Sentry in the helper process if the user opted in via the host app.
// CFPreferencesCopyValue reads the host app's preference domain directly, which is
// safe in this non-sandboxed helper process and avoids any IPC or file-sharing setup.
let consentValue = CFPreferencesCopyValue(
    "OESentryCrashReportingEnabled" as CFString,
    "org.openemu.OpenEmu" as CFString,
    kCFPreferencesAnyUser,
    kCFPreferencesAnyHost
)
if (consentValue as? Bool) == true {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    SentrySDK.start { options in
        options.dsn         = "https://387777a8153aae33cb514deea3601946@o4511164820815872.ingest.us.sentry.io/4511164891529216"
        options.releaseName = "openemu-silicon@\(version)+\(build)"
        options.environment = "production"
        options.debug       = false
    }
}

if let wait = ProcessInfo.processInfo.environment["OE_HELPER_WAIT_FOR_DEBUGGER"] as? NSString, wait.boolValue {
    XPCDebugSupport.waitForDebugger(until: .distantFuture)
}

OpenEmuXPCHelperApp.run()
